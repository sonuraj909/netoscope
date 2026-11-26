import Foundation

/// Captures HTTP(S) traffic made through `URLSession` and `NSURLConnection`.
///
/// `install` registers it globally, which covers `URLSession.shared`.
/// Sessions with a custom configuration need `enable(on:)`, or
/// `install(captureAllSessions: true)` to add it to every
/// `URLSessionConfiguration.default` and `.ephemeral`.
///
/// It only observes: each request is re-issued unchanged and responses,
/// data, redirects and authentication challenges are relayed to the
/// original client. At most `maxBodyBytes` of each body is recorded.
public final class NetoscopeURLProtocol: URLProtocol, URLSessionDataDelegate {
  private static let handledKey = "dev.netoscope.handled"
  public static var maxBodyBytes = 1024 * 1024
  private static var installed = false
  private static var swizzled = false

  /// Registers the protocol. Safe to call more than once.
  public static func install(captureAllSessions: Bool = false) {
    if !installed {
      URLProtocol.registerClass(NetoscopeURLProtocol.self)
      installed = true
    }
    if captureAllSessions && !swizzled {
      swizzled = true
      URLSessionConfiguration.netoscopeSwizzleFactories()
    }
  }

  /// Adds the protocol to [configuration] (before creating a session).
  public static func enable(on configuration: URLSessionConfiguration) {
    var classes = configuration.protocolClasses ?? []
    if !classes.contains(where: { $0 == NetoscopeURLProtocol.self }) {
      classes.insert(NetoscopeURLProtocol.self, at: 0)
      configuration.protocolClasses = classes
    }
  }

  private var innerSession: URLSession?
  private var innerTask: URLSessionDataTask?
  private var response: URLResponse?
  private var responseData = Data()
  private var requestBody: Data?
  private var redirected = false
  private let startedAt = Date()
  private let start = DispatchTime.now()

  public override class func canInit(with request: URLRequest) -> Bool {
    guard let scheme = request.url?.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    else { return false }
    return URLProtocol.property(forKey: handledKey, in: request) == nil
  }

  public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  public override func startLoading() {
    guard let mutable = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
      return
    }
    URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutable)
    // URLSession hands protocols the body as a stream; read it once and send
    // it as data so the real request is unchanged.
    if mutable.httpBody == nil, let stream = request.httpBodyStream {
      let data = Self.read(stream)
      mutable.httpBodyStream = nil
      mutable.httpBody = data
      requestBody = data
    } else {
      requestBody = mutable.httpBody
    }
    let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    innerSession = session
    innerTask = session.dataTask(with: mutable as URLRequest)
    innerTask?.resume()
  }

  public override func stopLoading() {
    innerTask?.cancel()
    innerSession?.invalidateAndCancel()
  }

  public func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    self.response = response
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    completionHandler(.allow)
  }

  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    let room = Self.maxBodyBytes - responseData.count
    if room > 0 { responseData.append(data.prefix(room)) }
    client?.urlProtocol(self, didLoad: data)
  }

  public func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    // Let the client follow the redirect; the new request is captured again.
    guard let redirect = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
      completionHandler(request)
      return
    }
    URLProtocol.removeProperty(forKey: Self.handledKey, in: redirect)
    redirected = true
    client?.urlProtocol(self, wasRedirectedTo: redirect as URLRequest, redirectResponse: response)
    completionHandler(nil)
  }

  public func urlSession(
    _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    completionHandler(.performDefaultHandling, nil)
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    defer { session.finishTasksAndInvalidate() }
    // The client follows redirects itself; the new request is captured on
    // its own, so this hop is neither failed nor recorded.
    if redirected { return }
    if let error = error {
      client?.urlProtocol(self, didFailWithError: error)
    } else {
      client?.urlProtocolDidFinishLoading(self)
    }
    record(error: error)
  }

  private func record(error: Error?) {
    let elapsed = (DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1000
    var event: [String: Any] = [
      "source": "ios",
      "method": request.httpMethod ?? "GET",
      "url": request.url?.absoluteString ?? "",
      "startedAt": Int(startedAt.timeIntervalSince1970 * 1000),
      "durationMicros": Int(elapsed),
      "requestHeaders": request.allHTTPHeaderFields ?? [:],
    ]
    if let body = requestBody, !body.isEmpty {
      event["requestBody"] = FlutterStandardTypedDataShim.wrap(body.prefix(Self.maxBodyBytes))
    }
    if let http = response as? HTTPURLResponse {
      event["statusCode"] = http.statusCode
      var headers: [String: String] = [:]
      for (key, value) in http.allHeaderFields { headers["\(key)"] = "\(value)" }
      event["responseHeaders"] = headers
      if !responseData.isEmpty { event["responseBody"] = FlutterStandardTypedDataShim.wrap(responseData) }
    }
    if let error = error as NSError? {
      event["error"] = error.localizedDescription
      event["errorType"] = Self.errorType(error)
    }
    NetoscopeBridge.shared.emit(event)
  }

  private static func errorType(_ error: NSError) -> String {
    guard error.domain == NSURLErrorDomain else { return "unknown" }
    switch error.code {
    case NSURLErrorTimedOut: return "timeout"
    case NSURLErrorCancelled: return "cancelled"
    case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
      NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet,
      NSURLErrorDNSLookupFailed:
      return "connection"
    case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
      NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateNotYetValid,
      NSURLErrorServerCertificateHasUnknownRoot:
      return "badCertificate"
    default: return "unknown"
    }
  }

  private static func read(_ stream: InputStream) -> Data {
    var data = Data()
    stream.open()
    defer { stream.close() }
    let size = 16 * 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
      let count = stream.read(buffer, maxLength: size)
      if count <= 0 { break }
      data.append(buffer, count: count)
    }
    return data
  }
}

extension URLSessionConfiguration {
  /// Swaps the `.default` and `.ephemeral` factories for versions that add
  /// `NetoscopeURLProtocol`.
  static func netoscopeSwizzleFactories() {
    let pairs: [(Selector, Selector)] = [
      (#selector(getter: URLSessionConfiguration.default),
       #selector(getter: URLSessionConfiguration.netoscopeDefault)),
      (#selector(getter: URLSessionConfiguration.ephemeral),
       #selector(getter: URLSessionConfiguration.netoscopeEphemeral)),
    ]
    for (original, replacement) in pairs {
      guard let a = class_getClassMethod(URLSessionConfiguration.self, original),
        let b = class_getClassMethod(URLSessionConfiguration.self, replacement)
      else { continue }
      method_exchangeImplementations(a, b)
    }
  }

  // After swizzling, these call the original implementations.
  @objc class var netoscopeDefault: URLSessionConfiguration {
    let configuration = self.netoscopeDefault
    NetoscopeURLProtocol.enable(on: configuration)
    return configuration
  }

  @objc class var netoscopeEphemeral: URLSessionConfiguration {
    let configuration = self.netoscopeEphemeral
    NetoscopeURLProtocol.enable(on: configuration)
    return configuration
  }
}
