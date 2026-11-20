package com.m5dev.libreshare

import android.content.Context
import android.os.Environment
import android.os.StatFs
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Reports total / free / used bytes for the primary storage volume.
 *
 * [Environment.getDataDirectory] (/data) is the authoritative internal volume.
 * StatFs only needs the path to exist, not to be readable, so /data works even
 * on locked-down builds; the fallbacks exist for the rare device where the path
 * is missing entirely. The channel reply is synchronous because StatFs is a
 * cheap syscall, but every failure still answers with an error instead of
 * leaving Dart waiting forever.
 */
object StorageInfoHandler {

    fun getStorageInfo(context: Context, result: MethodChannel.Result) {
        val candidates = listOfNotNull(
            Environment.getDataDirectory(),
            context.filesDir,
            context.getExternalFilesDir(null),
            Environment.getExternalStorageDirectory(),
        )

        var lastError: String? = null
        for (dir in candidates) {
            val info = readVolume(dir)
            if (info != null) {
                result.success(info)
                return
            }
            lastError = "StatFs returned no blocks for ${dir.path}"
        }

        result.error("STORAGE_FAILED", lastError ?: "No readable storage volume", null)
    }

    private fun readVolume(dir: File): Map<String, String>? = try {
        if (!dir.exists()) return null
        val stat = StatFs(dir.path)
        val blockSize = stat.blockSizeLong
        val total = stat.blockCountLong * blockSize
        val free = stat.availableBlocksLong * blockSize
        if (total <= 0L || blockSize <= 0L) {
            null
        } else {
            mapOf(
                "total" to total.toString(),
                "free" to free.toString(),
                "used" to (total - free).coerceAtLeast(0L).toString(),
                "path" to dir.path,
            )
        }
    } catch (_: Exception) {
        null
    }
}
