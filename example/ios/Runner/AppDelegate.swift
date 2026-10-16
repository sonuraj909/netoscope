import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Lets flutter_local_notifications (used by netoscope_notifications)
    // receive notification taps and present notifications in the foreground.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    GeneratedPluginRegistrant.register(with: self)

    // Native demo: requests through URLSession (captured by netoscope_native).
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "netoscope_example/native", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        guard call.method == "request",
          let args = call.arguments as? [String: Any],
          let urlString = args["url"] as? String,
          let url = URL(string: urlString)
        else {
          result(FlutterMethodNotImplemented)
          return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer native-secret", forHTTPHeaderField: "Authorization")
        if let body = args["body"] as? String {
          request.httpMethod = "POST"
          request.setValue("application/json", forHTTPHeaderField: "Content-Type")
          request.httpBody = body.data(using: .utf8)
        }
        // "custom" uses a session created from URLSessionConfiguration.default,
        // captured because the app attaches with captureAllUrlSessions: true.
        let custom = (args["session"] as? String) == "custom"
        let session = custom ? URLSession(configuration: .default) : URLSession.shared
        session.dataTask(with: request) { _, response, error in
          DispatchQueue.main.async {
            if let error = error {
              result(FlutterError(code: "request", message: error.localizedDescription, details: nil))
            } else {
              let code = (response as? HTTPURLResponse)?.statusCode ?? 0
              result("URLSession\(custom ? " (custom)" : "") \(code)")
            }
          }
        }.resume()
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
