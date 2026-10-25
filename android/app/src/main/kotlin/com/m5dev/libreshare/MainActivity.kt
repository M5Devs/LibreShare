package com.m5dev.libreshare

import android.media.MediaScannerConnection
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "com.m5dev.libreshare/hotspot").setMethodCallHandler { call, result ->
            when (call.method) {
                "startHotspot" -> HotspotController.start(
                    applicationContext,
                    onSuccess = { i ->
                        result.success(mapOf("ssid" to i.ssid, "password" to i.password, "ip" to i.ip, "iface" to i.iface))
                    },
                    onError = { code, msg -> result.error(code, msg, null) }
                )
                "stopHotspot" -> {
                    HotspotController.stop()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "com.m5dev.libreshare/service").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> {
                        LibreShareService.start(this, call.argument<String>("text") ?: "Sharing files")
                        result.success(true)
                    }
                    "update" -> {
                        LibreShareService.update(this, call.argument<String>("text") ?: "Sharing files")
                        result.success(true)
                    }
                    "stop" -> {
                        LibreShareService.stop(this)
                        result.success(true)
                    }
                    "scanMediaFile" -> {
                        val path = call.argument<String>("path")
                        if (path != null) {
                            MediaScannerConnection.scanFile(applicationContext, arrayOf(path), null) { scannedPath, uri -> }
                            result.success(true)
                        } else {
                            result.error("INVALID_PATH", "Path is null", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("SERVICE_FAILED", e.message, null)
            }
        }

        EventChannel(messenger, "com.m5dev.libreshare/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    NativeEvents.sink = events
                }
                override fun onCancel(arguments: Any?) {
                    NativeEvents.sink = null
                }
            }
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        NativeEvents.sink = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
