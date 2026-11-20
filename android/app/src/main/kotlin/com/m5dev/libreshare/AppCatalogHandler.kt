package com.m5dev.libreshare

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

/**
 * Enumerates the apps installed on the device so the picker can offer their
 * APKs for sharing.
 *
 * Uses [PackageManager.getInstalledApplications] rather than a launcher-intent
 * query: launcher queries only return apps with a launcher activity, which
 * silently drops shareable-but-headless packages. System apps are filtered out
 * so the list contains things the user can actually send.
 *
 * Icons and APK sizes are read here because both are expensive and must not run
 * on the UI thread; the whole enumeration happens on a worker thread. The
 * MethodChannel reply is marshalled back to the main thread, which the channel
 * requires.
 */
object AppCatalogHandler {

    private const val ICON_PX = 96

    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "libreshare-app-catalog").apply { isDaemon = true }
    }

    fun listInstalledApps(context: Context, result: MethodChannel.Result) {
        val appContext = context.applicationContext
        worker.execute {
            try {
                val apps = collect(appContext)
                mainHandler.post { result.success(apps) }
            } catch (e: Throwable) {
                mainHandler.post { result.error("APP_LIST_FAILED", e.message, null) }
            }
        }
    }

    private fun collect(context: Context): List<Map<String, Any?>> {
        val pm = context.packageManager
        @Suppress("DEPRECATION")
        val installed = pm.getInstalledApplications(PackageManager.GET_META_DATA)

        val apps = ArrayList<Map<String, Any?>>(installed.size)
        for (appInfo in installed) {
            if (!isShareable(pm, appInfo)) continue

            val sourceDir = appInfo.sourceDir ?: continue
            val label = try {
                pm.getApplicationLabel(appInfo).toString()
            } catch (_: Exception) {
                appInfo.packageName
            }

            apps.add(
                mapOf(
                    "label" to label,
                    "packageName" to appInfo.packageName,
                    "apkPath" to sourceDir,
                    "size" to apkSize(appInfo).toString(),
                    "icon" to iconBytes(pm, appInfo),
                    "system" to appInfo.isSystemApp(),
                )
            )
        }

        apps.sortBy { (it["label"] as? String)?.lowercase() ?: "" }
        return apps
    }

    /**
     * Keeps user-installed apps plus any package that still exposes a launcher
     * entry (some vendor apps are flagged as system but are user-facing).
     */
    private fun isShareable(pm: PackageManager, appInfo: ApplicationInfo): Boolean {
        if (!appInfo.isSystemApp()) return true
        val launchIntent: Intent? = pm.getLaunchIntentForPackage(appInfo.packageName)
        return launchIntent != null
    }

    @Suppress("DEPRECATION")
    private fun ApplicationInfo.isSystemApp(): Boolean =
        (flags and ApplicationInfo.FLAG_SYSTEM) != 0 &&
            (flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0

    /**
     * Total on-disk size of an app: the base APK plus every split APK in its
     * source directory. Modern apps ship most of their code as splits, so the
     * base file alone would report a fraction of the real size.
     */
    private fun apkSize(appInfo: ApplicationInfo): Long {
        val sourceDir = appInfo.sourceDir ?: return 0L
        val base = File(sourceDir)
        val splits = appInfo.splitSourceDirs
        var total = if (base.isFile) base.length() else 0L
        splits?.forEach { path ->
            val split = File(path)
            if (split.isFile) total += split.length()
        }
        return total
    }

    private fun iconBytes(pm: PackageManager, appInfo: ApplicationInfo): ByteArray? = try {
        encodeIcon(pm.getApplicationIcon(appInfo))
    } catch (_: Exception) {
        null
    }

    private fun encodeIcon(drawable: Drawable): ByteArray {
        val bitmap = when {
            drawable is BitmapDrawable && drawable.bitmap != null ->
                Bitmap.createScaledBitmap(drawable.bitmap, ICON_PX, ICON_PX, true)
            else -> {
                val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else ICON_PX
                val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else ICON_PX
                Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { bmp ->
                    val canvas = Canvas(bmp)
                    drawable.setBounds(0, 0, canvas.width, canvas.height)
                    drawable.draw(canvas)
                }.let { Bitmap.createScaledBitmap(it, ICON_PX, ICON_PX, true) }
            }
        }

        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        return out.toByteArray()
    }
}
