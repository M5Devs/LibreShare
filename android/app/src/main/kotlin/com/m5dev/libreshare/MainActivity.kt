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
                    "openFile" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("INVALID_PATH", "Path is null", null)
                        } else {
                            result.success(openFile(path, call.argument<String>("mime")))
                        }
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

        MethodChannel(messenger, "com.m5dev.libreshare/catalog").setMethodCallHandler { call, result ->
            when (call.method) {
                "listInstalledApps" -> AppCatalogHandler.listInstalledApps(applicationContext, result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "com.m5dev.libreshare/media").setMethodCallHandler { call, result ->
            when (call.method) {
                "listMedia" -> MediaStoreHandler.listMedia(applicationContext, result)
                "countMedia" -> MediaStoreHandler.countMedia(applicationContext, result)
                "thumbnail" -> MediaStoreHandler.loadThumbnail(
                    applicationContext,
                    call.argument<String>("uri"),
                    result,
                )
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "com.m5dev.libreshare/storage").setMethodCallHandler { call, result ->
            when (call.method) {
                "getStorageInfo" -> {
                    try {
                        StorageInfoHandler.getStorageInfo(applicationContext, result)
                    } catch (e: Exception) {
                        result.error("STORAGE_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
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

    /**
     * Hands a file to whichever app can display it.
     *
     * `file://` URIs are rejected by Android 7+, so the path goes through our
     * FileProvider and the receiving app gets a temporary read grant. A missing
     * handler (no gallery, no PDF reader) is reported rather than swallowed.
     */
    private fun openFile(path: String, mime: String?): Boolean {
        val file = java.io.File(path)
        if (!file.exists()) return false

        val type = mime?.takeIf { it.isNotEmpty() }
            ?: android.webkit.MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(file.extension.lowercase())
            ?: "*/*"

        return try {
            val uri = androidx.core.content.FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file,
            )
            val intent = android.content.Intent(android.content.Intent.ACTION_VIEW).apply {
                setDataAndType(uri, type)
                addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            // No viewer installed, or the provider rejected the path.
            android.util.Log.w("LibreShare", "Cannot open $path: ${e.message}")
            false
        }
    }
}
