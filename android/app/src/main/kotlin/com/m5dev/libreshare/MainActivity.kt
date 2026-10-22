package com.m5dev.libreshare

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.m5dev.libreshare/hotspot"
    private var reservation: WifiManager.LocalOnlyHotspotReservation? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startHotspot" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        try {
                            wifiManager.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                                override fun onStarted(res: WifiManager.LocalOnlyHotspotReservation) {
                                    super.onStarted(res)
                                    reservation = res
                                    var ssid: String? = null
                                    var password: String? = null

                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                        val config = res.softApConfiguration
                                        ssid = config.ssid
                                        password = config.passphrase
                                    } else {
                                        @Suppress("DEPRECATION")
                                        val config = res.wifiConfiguration
                                        @Suppress("DEPRECATION")
                                        ssid = config?.SSID
                                        @Suppress("DEPRECATION")
                                        password = config?.preSharedKey
                                    }

                                    result.success(
                                        mapOf(
                                            "ssid" to (ssid ?: "LibreShare-Hotspot"),
                                            "password" to (password ?: ""),
                                            "ip" to "192.168.43.1"
                                        )
                                    )
                                }

                                override fun onFailed(reason: Int) {
                                    super.onFailed(reason)
                                    result.error("HOTSPOT_FAILED", "Failed with code: $reason", null)
                                }
                            }, null)
                        } catch (e: Exception) {
                            result.error("HOTSPOT_FAILED", e.message, null)
                        }
                    } else {
                        result.error("UNSUPPORTED", "LocalOnlyHotspot requires Android 8.0+", null)
                    }
                }
                "stopHotspot" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        reservation?.close()
                        reservation = null
                    }
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
