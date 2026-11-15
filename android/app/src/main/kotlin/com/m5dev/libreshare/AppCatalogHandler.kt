package com.m5dev.libreshare

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * Enumerates installed, launchable apps and returns their label, package name,
 * source APK path, APK size and a PNG-encoded launcher icon.
 *
 * The work runs on a background thread because PackageManager queries and icon
 * decoding are comparatively expensive.
 */
object AppCatalogHandler {

    fun listInstalledApps(context: Context, result: MethodChannel.Result) {
        Thread {
            try {
                val pm = context.packageManager
                val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                @Suppress("DEPRECATION")
                val packages = pm.queryIntentActivities(intent, 0)

                val apps = ArrayList<Map<String, Any?>>()
                for (info in packages) {
                    val activityInfo = info.activityInfo ?: continue
                    val appInfo: ApplicationInfo = activityInfo.applicationInfo
                    val sourceDir = appInfo.sourceDir ?: continue
                    val label = pm.getApplicationLabel(appInfo).toString()
                    val size = try {
                        File(sourceDir).length()
                    } catch (_: Exception) {
                        0L
                    }

                    val iconBytes = try {
                        encodeIcon(pm.getApplicationIcon(appInfo))
                    } catch (_: Exception) {
                        null
                    }

                    apps.add(
                        mapOf(
                            "label" to label,
                            "packageName" to appInfo.packageName,
                            "apkPath" to sourceDir,
                            "size" to size.toString(),
                            "icon" to iconBytes,
                        )
                    )
                }

                apps.sortBy { (it["label"] as? String)?.lowercase() ?: "" }
                result.success(apps)
            } catch (e: Exception) {
                result.error("APP_LIST_FAILED", e.message, null)
            }
        }.start()
    }

    private fun encodeIcon(drawable: Drawable): ByteArray? {
        val bitmap: Bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            drawable.bitmap
        } else {
            val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 96
            val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 96
            Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { bmp ->
                val canvas = Canvas(bmp)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
            }
        }

        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        return out.toByteArray()
    }
}
