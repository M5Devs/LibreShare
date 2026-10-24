package com.m5dev.libreshare

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.Collections

data class IfaceAddr(val iface: String, val ip: String)

object HotspotIpDetector {
    private val excludedParts = listOf(
        "rmnet", "ccmni", "ccemni", "seth", "clat", "dummy", "v4-", "tun", "tap", "ppp", "docker", "veth"
    )
    private val apLike = Regex("^(ap\\d*|swlan\\d*|softap\\d*|wlan[1-9]\\d*|p2p.*)$", RegexOption.IGNORE_CASE)

    private fun isExcluded(name: String): Boolean {
        val n = name.lowercase()
        return excludedParts.any { n.contains(it) }
    }

    private fun currentAddrs(): List<IfaceAddr> {
        val out = ArrayList<IfaceAddr>()
        val raw = try { NetworkInterface.getNetworkInterfaces() } catch (e: Exception) { null } ?: return out
        for (ni in Collections.list(raw)) {
            try {
                if (!ni.isUp || ni.isLoopback) continue
                for (addr in Collections.list(ni.inetAddresses)) {
                    if (addr is Inet4Address && addr.isSiteLocalAddress) {
                        val host = addr.hostAddress ?: continue
                        out.add(IfaceAddr(ni.name, host))
                    }
                }
            } catch (_: Exception) {}
        }
        return out
    }

    fun snapshot(): Set<IfaceAddr> = currentAddrs().toSet()

    fun pickNew(before: Set<IfaceAddr>, after: List<IfaceAddr>): IfaceAddr? {
        val candidates = after.filter { it !in before && !isExcluded(it.iface) }
        if (candidates.isEmpty()) return null
        val knownNames = before.map { it.iface }.toSet()
        val brandNew = candidates.filter { it.iface !in knownNames }
        val pool = if (brandNew.isNotEmpty()) brandNew else candidates
        return pool.firstOrNull { apLike.matches(it.iface) } ?: pool.first()
    }

    fun pickApLike(after: List<IfaceAddr>): IfaceAddr? =
        after.firstOrNull { apLike.matches(it.iface) && !isExcluded(it.iface) }

    fun awaitHotspotIp(
        before: Set<IfaceAddr>,
        timeoutMs: Long = 6000,
        intervalMs: Long = 250,
        onResult: (IfaceAddr?) -> Unit
    ) {
        val handler = Handler(Looper.getMainLooper())
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        val tick = object : Runnable {
            override fun run() {
                val now = currentAddrs()
                val found = pickNew(before, now)
                if (found != null) {
                    onResult(found)
                    return
                }
                if (SystemClock.elapsedRealtime() >= deadline) {
                    onResult(pickApLike(now))
                    return
                }
                handler.postDelayed(this, intervalMs)
            }
        }
        tick.run()
    }
}
