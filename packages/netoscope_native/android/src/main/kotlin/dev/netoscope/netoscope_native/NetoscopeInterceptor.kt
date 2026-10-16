package dev.netoscope.netoscope_native

import java.io.IOException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import javax.net.ssl.SSLException
import okhttp3.Headers
import okhttp3.Interceptor
import okhttp3.MediaType
import okhttp3.Request
import okhttp3.Response
import okio.Buffer

/**
 * An OkHttp interceptor that records every call to Netoscope.
 *
 * Add it to the OkHttp clients your native code uses:
 *
 * ```kotlin
 * val client = OkHttpClient.Builder()
 *     .addInterceptor(NetoscopeInterceptor())
 *     .build()
 * ```
 *
 * It only observes: the request and response are passed on unchanged.
 * Response bodies are read with `peekBody`, so the app still reads the full
 * body; only textual bodies are peeked, and at most [maxBodyBytes] of them.
 * Streaming (`text/event-stream`), media and one-shot/duplex bodies are not
 * read. Values are redacted in Dart before they are stored or shown.
 */
class NetoscopeInterceptor @JvmOverloads constructor(
    private val maxBodyBytes: Long = 1024L * 1024L,
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val startedAt = System.currentTimeMillis()
        val start = System.nanoTime()
        val requestBody = requestBody(request)

        val response = try {
            chain.proceed(request)
        } catch (error: IOException) {
            NetoscopeBridge.emit(
                event(request, startedAt, start, requestBody) + mapOf(
                    "error" to (error.message ?: error.javaClass.simpleName),
                    "errorType" to errorType(error),
                ),
            )
            throw error
        }

        NetoscopeBridge.emit(
            event(request, startedAt, start, requestBody) + mapOf(
                "statusCode" to response.code,
                "responseHeaders" to headers(response.headers),
                "responseBody" to responseBody(response),
            ),
        )
        return response
    }

    private fun event(
        request: Request,
        startedAt: Long,
        start: Long,
        requestBody: ByteArray?,
    ): Map<String, Any?> = mapOf(
        "source" to "android",
        "method" to request.method,
        "url" to request.url.toString(),
        "startedAt" to startedAt,
        "durationMicros" to (System.nanoTime() - start) / 1000,
        "requestHeaders" to headers(request.headers, request.body?.contentType()),
        "requestBody" to requestBody,
    )

    private fun requestBody(request: Request): ByteArray? {
        val body = request.body ?: return null
        return try {
            if (body.isDuplex() || body.isOneShot()) return null
            val length = body.contentLength()
            if (length > maxBodyBytes) return null
            Buffer().also { body.writeTo(it) }.readByteArray()
        } catch (_: Exception) {
            null
        }
    }

    private fun responseBody(response: Response): ByteArray? {
        val type = response.body?.contentType()
        if (!isTextual(type)) return null
        return try {
            response.peekBody(maxBodyBytes).bytes()
        } catch (_: Exception) {
            null
        }
    }

    private fun isTextual(type: MediaType?): Boolean {
        if (type == null) return false
        val full = "${type.type}/${type.subtype}".lowercase()
        if (full == "text/event-stream") return false
        return type.type == "text" ||
            listOf("json", "xml", "x-www-form-urlencoded", "graphql", "javascript")
                .any { full.contains(it) }
    }

    private fun headers(headers: Headers, contentType: MediaType? = null): Map<String, String> {
        val result = LinkedHashMap<String, String>()
        for (name in headers.names()) result[name] = headers.values(name).joinToString(", ")
        if (contentType != null && result.keys.none { it.equals("content-type", true) }) {
            result["Content-Type"] = contentType.toString()
        }
        return result
    }

    private fun errorType(error: IOException): String = when {
        error is SocketTimeoutException -> "timeout"
        error is UnknownHostException || error is ConnectException ||
            error is NoRouteToHostException -> "connection"
        error is SSLException -> "badCertificate"
        error.message.equals("Canceled", ignoreCase = true) -> "cancelled"
        else -> "unknown"
    }
}
