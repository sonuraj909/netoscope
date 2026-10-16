package dev.netoscope.netoscope_native

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Delivers captured calls to Dart on the main thread. Calls captured before
 * Dart starts listening are kept (up to [MAX_PENDING]) and delivered later.
 */
object NetoscopeBridge {
    private const val MAX_PENDING = 50

    private val main = Handler(Looper.getMainLooper())
    private val pending = ArrayDeque<Map<String, Any?>>()
    private var sink: EventChannel.EventSink? = null

    internal fun attach(events: EventChannel.EventSink) {
        main.post {
            sink = events
            while (pending.isNotEmpty()) events.success(pending.removeFirst())
        }
    }

    internal fun detach() {
        main.post { sink = null }
    }

    /** Sends one captured call. Safe to call from any thread. */
    fun emit(call: Map<String, Any?>) {
        main.post {
            val events = sink
            if (events != null) {
                events.success(call)
            } else {
                pending.addLast(call)
                while (pending.size > MAX_PENDING) pending.removeFirst()
            }
        }
    }
}
