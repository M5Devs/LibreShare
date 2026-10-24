package com.m5dev.libreshare

import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.*

class LibreShareService : Service() {
    companion object {
        const val ACTION_START = "com.m5dev.libreshare.action.START"
        const val ACTION_UPDATE = "com.m5dev.libreshare.action.UPDATE"
        const val ACTION_STOP = "com.m5dev.libreshare.action.STOP"
        const val EXTRA_TEXT = "text"
        private const val CHANNEL_ID = "libreshare_transfer"
        private const val NOTIFICATION_ID = 5001
        private const val WAKELOCK_TIMEOUT_MS = 8L * 60 * 60 * 1000

        @Volatile var isRunning: Boolean = false
            private set

        fun start(ctx: Context, text: String) {
            val i = Intent(ctx, LibreShareService::class.java).setAction(ACTION_START).putExtra(EXTRA_TEXT, text)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) ctx.startForegroundService(i) else ctx.startService(i)
        }
        fun update(ctx: Context, text: String) {
            if (!isRunning) return
            ctx.startService(Intent(ctx, LibreShareService::class.java).setAction(ACTION_UPDATE).putExtra(EXTRA_TEXT, text))
        }
        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, LibreShareService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: "Sharing files on local network"
        when (intent?.action) {
            ACTION_STOP -> {
                HotspotController.stop()
                NativeEvents.emit("stop_requested")
                shutdown()
            }
            ACTION_UPDATE -> {
                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.notify(NOTIFICATION_ID, buildNotification(text))
            }
            else -> {
                if (enterForeground(text)) {
                    acquireLocks()
                    isRunning = true
                } else stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        HotspotController.stop()
        shutdown()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        releaseLocks()
        isRunning = false
        super.onDestroy()
    }

    private fun enterForeground(text: String): Boolean {
        return try {
            createChannel()
            val n = buildNotification(text)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            } else {
                startForeground(NOTIFICATION_ID, n)
            }
            true
        } catch (e: Exception) {
            NativeEvents.emit("service_error", mapOf("message" to (e.message ?: e.javaClass.simpleName)))
            false
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            val ch = NotificationChannel(CHANNEL_ID, "LibreShare transfers", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown while LibreShare is serving files"
                setShowBadge(false)
            }
            nm.createNotificationChannel(ch)
        }
    }

    @Suppress("DEPRECATION")
    private fun buildNotification(text: String): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPi = PendingIntent.getActivity(this, 0, openIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val stopPi = PendingIntent.getService(this, 1, Intent(this, LibreShareService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        builder.setContentTitle("LibreShare")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setContentIntent(openPi)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPi)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build()
    }

    @Suppress("DEPRECATION")
    private fun acquireLocks() {
        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "LibreShare:server").apply {
                setReferenceCounted(false)
                acquire(WAKELOCK_TIMEOUT_MS)
            }
        }
        if (wifiLock == null) {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) WifiManager.WIFI_MODE_FULL_LOW_LATENCY else WifiManager.WIFI_MODE_FULL_HIGH_PERF
            wifiLock = wm.createWifiLock(mode, "LibreShare:wifi").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    private fun releaseLocks() {
        try { wakeLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        try { wifiLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        wakeLock = null
        wifiLock = null
    }

    @Suppress("DEPRECATION")
    private fun shutdown() {
        releaseLocks()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(Service.STOP_FOREGROUND_REMOVE) else stopForeground(true)
        isRunning = false
        stopSelf()
    }
}
