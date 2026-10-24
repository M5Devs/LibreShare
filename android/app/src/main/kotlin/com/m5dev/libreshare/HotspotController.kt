package com.m5dev.libreshare

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper

object HotspotController {
    data class Info(val ssid: String, val password: String, val ip: String, val iface: String)

    @Volatile private var reservation: WifiManager.LocalOnlyHotspotReservation? = null
    @Volatile private var info: Info? = null

    fun start(
        context: Context,
        onSuccess: (Info) -> Unit,
        onError: (code: String, message: String?) -> Unit
    ) {
        val existing = info
        if (existing != null && reservation != null) {
            onSuccess(existing)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            onError("UNSUPPORTED", "LocalOnlyHotspot requires Android 8.0+")
            return
        }
        val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val before = HotspotIpDetector.snapshot()
        var replied = false

        try {
            wifiManager.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(res: WifiManager.LocalOnlyHotspotReservation) {
                    reservation = res
                    val (ssid, password) = readCredentials(res)
                    HotspotIpDetector.awaitHotspotIp(before) { found ->
                        if (replied) return@awaitHotspotIp
                        replied = true
                        if (found == null) {
                            try { res.close() } catch (_: Exception) {}
                            reservation = null
                            onError("HOTSPOT_IP_NOT_FOUND", "Hotspot started but IP was not detected")
                        } else {
                            val i = Info(ssid, password, found.ip, found.iface)
                            info = i
                            onSuccess(i)
                        }
                    }
                }
                override fun onStopped() {
                    reservation = null
                    info = null
                    NativeEvents.emit("hotspot_stopped")
                }
                override fun onFailed(reason: Int) {
                    if (replied) return
                    replied = true
                    onError("HOTSPOT_FAILED", "reason=$reason")
                }
            }, Handler(Looper.getMainLooper()))
        } catch (e: SecurityException) {
            if (!replied) { replied = true; onError("PERMISSION_DENIED", e.message) }
        } catch (e: Exception) {
            if (!replied) { replied = true; onError("HOTSPOT_FAILED", e.message) }
        }
    }

    fun stop() {
        try { reservation?.close() } catch (_: Exception) {}
        reservation = null
        info = null
    }

    @Suppress("DEPRECATION")
    private fun readCredentials(res: WifiManager.LocalOnlyHotspotReservation): Pair<String, String> {
        val ssid: String?
        val pass: String?
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            ssid = res.softApConfiguration.ssid
            pass = res.softApConfiguration.passphrase
        } else {
            ssid = res.wifiConfiguration?.SSID
            pass = res.wifiConfiguration?.preSharedKey
        }
        return Pair(unquote(ssid) ?: "LibreShare-Hotspot", unquote(pass) ?: "")
    }

    private fun unquote(s: String?): String? =
        if (s != null && s.length >= 2 && s.startsWith("\"") && s.endsWith("\"")) s.substring(1, s.length - 1) else s
}
