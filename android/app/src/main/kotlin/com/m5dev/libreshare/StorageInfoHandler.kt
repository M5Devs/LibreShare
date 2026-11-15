package com.m5dev.libreshare

import android.content.Context
import android.os.Environment
import android.os.StatFs
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Reports total / free / used bytes for the primary storage volume.
 *
 * [Environment.getDataDirectory] (/data) is the authoritative internal volume
 * but is unreadable on a few locked-down builds, so this falls back to the
 * app's own files directory and then to external storage before giving up.
 */
object StorageInfoHandler {

    fun getStorageInfo(context: Context, result: MethodChannel.Result) {
        val candidate: File? = pickVolume(context)
        if (candidate == null) {
            result.error("STORAGE_FAILED", "No readable storage volume", null)
            return
        }

        try {
            val stat = StatFs(candidate.path)
            val total = stat.blockCountLong * stat.blockSizeLong
            val free = stat.availableBlocksLong * stat.blockSizeLong
            result.success(
                mapOf(
                    "total" to total.toString(),
                    "free" to free.toString(),
                    "used" to (total - free).coerceAtLeast(0L).toString(),
                    "path" to candidate.path,
                )
            )
        } catch (e: Exception) {
            result.error("STORAGE_FAILED", e.message, null)
        }
    }

    private fun pickVolume(context: Context): File? {
        val candidates = listOf(
            Environment.getDataDirectory(),
            context.filesDir,
            context.getExternalFilesDir(null),
            Environment.getExternalStorageDirectory(),
        )
        for (dir in candidates) {
            if (dir == null) continue
            try {
                val stat = StatFs(dir.path)
                if (stat.blockCountLong > 0L && stat.blockSizeLong > 0L) return dir
            } catch (_: Exception) {
                // Try the next volume.
            }
        }
        return null
    }
}
