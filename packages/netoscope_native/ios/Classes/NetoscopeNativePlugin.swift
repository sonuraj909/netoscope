import Flutter
import UIKit

/// Streams calls captured by `NetoscopeURLProtocol` to Dart.
public class NetoscopeNativePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = NetoscopeNativePlugin()
    let calls = FlutterEventChannel(
      name: "dev.netoscope/native_calls", binaryMessenger: registrar.messenger())
    calls.setStreamHandler(instance)
    let control = FlutterMethodChannel(
      name: "dev.netoscope/native_control", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: control)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "configure":
      let args = call.arguments as? [String: Any]
      let all = args?["captureAllUrlSessions"] as? Bool ?? false
      NetoscopeURLProtocol.install(captureAllSessions: all)
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    NetoscopeBridge.shared.attach(events)
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    NetoscopeBridge.shared.detach()
    return nil
  }
}

/// Delivers captured calls to Dart on the main thread. Calls captured before
/// Dart starts listening are kept (up to 50) and delivered later.
final class NetoscopeBridge {
  static let shared = NetoscopeBridge()

  private var sink: FlutterEventSink?
  private var pending: [[String: Any]] = []

  func attach(_ events: @escaping FlutterEventSink) {
    DispatchQueue.main.async {
      self.sink = events
      for event in self.pending { events(event) }
      self.pending.removeAll()
    }
  }

  func detach() {
    DispatchQueue.main.async { self.sink = nil }
  }

  func emit(_ event: [String: Any]) {
    DispatchQueue.main.async {
      if let sink = self.sink {
        sink(event)
      } else {
        self.pending.append(event)
        if self.pending.count > 50 { self.pending.removeFirst() }
      }
    }
  }
}
