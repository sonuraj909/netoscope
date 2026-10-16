package dev.netoscope.netoscope_example

import dev.netoscope.netoscope_native.NetoscopeInterceptor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import kotlin.concurrent.thread

/** Native demo: performs requests with OkHttp + NetoscopeInterceptor. */
class MainActivity : FlutterActivity() {
    private val client = OkHttpClient.Builder()
        .addInterceptor(NetoscopeInterceptor())
        .build()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "netoscope_example/native")
            .setMethodCallHandler { call, result ->
                val url = call.argument<String>("url")
                if (call.method != "request" || url == null) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val body = call.argument<String>("body")
                thread {
                    try {
                        val builder = Request.Builder().url(url)
                            .header("Authorization", "Bearer native-secret")
                        if (body != null) {
                            builder.post(body.toRequestBody("application/json".toMediaType()))
                        }
                        client.newCall(builder.build()).execute().use { response ->
                            val code = response.code
                            response.body?.string()
                            runOnUiThread { result.success("OkHttp $code") }
                        }
                    } catch (error: Exception) {
                        runOnUiThread { result.error("request", error.message, null) }
                    }
                }
            }
    }
}
