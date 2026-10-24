package com.m5dev.libreshare

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object NativeEvents {
    @Volatile var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())

    fun emit(type: String, data: Map<String, Any?> = emptyMap()) {
        val payload = HashMap<String, Any?>(data)
        payload["type"] = type
        main.post { sink?.success(payload) }
    }
}
