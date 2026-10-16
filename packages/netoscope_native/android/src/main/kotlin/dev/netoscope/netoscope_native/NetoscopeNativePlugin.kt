package dev.netoscope.netoscope_native

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Streams calls captured by [NetoscopeInterceptor] to Dart. */
class NetoscopeNativePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private var calls: EventChannel? = null
    private var control: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        calls = EventChannel(binding.binaryMessenger, "dev.netoscope/native_calls")
            .also { it.setStreamHandler(this) }
        control = MethodChannel(binding.binaryMessenger, "dev.netoscope/native_control")
            .also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        calls?.setStreamHandler(null)
        control?.setMethodCallHandler(null)
        NetoscopeBridge.detach()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Nothing to configure on Android: apps add NetoscopeInterceptor.
            "configure" -> result.success(true)
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        NetoscopeBridge.attach(events)
    }

    override fun onCancel(arguments: Any?) {
        NetoscopeBridge.detach()
    }
}
