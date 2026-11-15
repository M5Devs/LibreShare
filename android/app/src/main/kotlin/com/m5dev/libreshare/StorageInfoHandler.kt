package com.m5dev.libreshare

import android.content.Context
import android.os.Environment
import android.os.StatFs
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Reports total and free bytes for the primary external storage volume. */
object StorageInfoHandler {

    fun getStorageInfo(context: Context, result: MethodChannel.Result) {
        try {
            val path: File = Environment.getDataDirectory()
            val stat = StatFs(path.path)
            val total = stat.blockCountLong * stat.blockSizeLong
            val free = stat.availableBlocksLong * stat.blockSizeLong
            result.success(mapOf("total" to total.toString(), "free" to free.toString()))
        } catch (e: Exception) {
            result.error("STORAGE_FAILED", e.message, null)
        }
    }
}
