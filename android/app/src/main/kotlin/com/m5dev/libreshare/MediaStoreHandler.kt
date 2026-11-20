package com.m5dev.libreshare

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Enumerates device media through the MediaStore content providers.
 *
 * This exists because walking the filesystem directly does not work on modern
 * Android: scoped storage (API 29+) hides `/storage/emulated/0` from `dart:io`,
 * so a directory walk returns nothing and the picker shows "0 photos" even
 * when the permission is granted. MediaStore is the only supported way to see
 * the user's media — and it is indexed, so it answers in milliseconds instead
 * of walking thousands of directory entries.
 *
 * Every category is queried independently so one failing provider (a device
 * with no audio index, say) cannot empty the others.
 */
object MediaStoreHandler {

    /** First page size. The picker renders this batch immediately. */
    private const val FIRST_PAGE = 200

    /** Hard ceiling for a single listing request. */
    private const val MAX_ITEMS = 5000

    private const val THUMB_PX = 192
    private const val THUMB_QUALITY = 80

    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "libreshare-media-store").apply { isDaemon = true }
    }

    /** Mime types that count as shareable documents. */
    private val documentMimes = arrayOf(
        "application/pdf",
        "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.ms-excel",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "application/vnd.ms-powerpoint",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "text/plain",
        "text/rtf",
        "text/csv",
        "application/zip",
        "application/x-rar-compressed",
        "application/x-7z-compressed",
        "application/gzip",
        "application/json",
        "text/xml",
        "application/vnd.android.package-archive",
    )

    fun listMedia(context: Context, result: MethodChannel.Result) {
        val appContext = context.applicationContext
        worker.execute {
            try {
                val payload = collect(appContext, FIRST_PAGE)
                mainHandler.post { result.success(payload) }
            } catch (e: Throwable) {
                mainHandler.post { result.error("MEDIA_LIST_FAILED", e.message, null) }
            }
        }
    }

    /**
     * Cheap `COUNT(*)` per category, for the storage screen.
     *
     * Counting rows is far cheaper than materialising them, so the Files screen
     * can show "Photos: 2,431" without waiting on a full listing.
     */
    fun countMedia(context: Context, result: MethodChannel.Result) {
        val appContext = context.applicationContext
        worker.execute {
            try {
                val selection = baseSelection()
                val payload = mapOf(
                    "photos" to count(appContext, MediaStore.Images.Media.EXTERNAL_CONTENT_URI, selection, null),
                    "videos" to count(appContext, MediaStore.Video.Media.EXTERNAL_CONTENT_URI, selection, null),
                    "music" to count(appContext, MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, selection, null),
                    "documents" to countDocuments(appContext),
                )
                mainHandler.post { result.success(payload) }
            } catch (e: Throwable) {
                mainHandler.post { result.error("MEDIA_COUNT_FAILED", e.message, null) }
            }
        }
    }

    /** JPEG bytes for one media row, or null when the platform cannot decode it. */
    fun loadThumbnail(context: Context, uriString: String?, result: MethodChannel.Result) {
        if (uriString.isNullOrEmpty()) {
            result.success(null)
            return
        }
        val appContext = context.applicationContext
        worker.execute {
            val bytes = try {
                decodeThumbnail(appContext, Uri.parse(uriString))
            } catch (_: Throwable) {
                null
            }
            mainHandler.post { result.success(bytes) }
        }
    }

    private fun decodeThumbnail(context: Context, uri: Uri): ByteArray? {
        val bitmap: Bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            context.contentResolver.loadThumbnail(uri, android.util.Size(THUMB_PX, THUMB_PX), null)
        } else {
            @Suppress("DEPRECATION")
            MediaStore.Images.Thumbnails.getThumbnail(
                context.contentResolver,
                ContentUris.parseId(uri),
                MediaStore.Images.Thumbnails.MINI_KIND,
                null,
            ) ?: return null
        }

        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, THUMB_QUALITY, out)
        bitmap.recycle()
        return out.toByteArray()
    }

    private fun collect(context: Context, limit: Int): Map<String, List<Map<String, Any?>>> {
        return mapOf(
            "photos" to queryCollection(context, MediaStore.Images.Media.EXTERNAL_CONTENT_URI, isVideo = false, limit = limit),
            "videos" to queryCollection(context, MediaStore.Video.Media.EXTERNAL_CONTENT_URI, isVideo = true, limit = limit),
            "music" to queryCollection(context, MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, isVideo = false, limit = limit),
            "documents" to queryDocuments(context, limit),
        )
    }

    /**
     * Filters shared by the listing and the count queries.
     *
     * Both must agree: if the listing skips a row, the count must skip it too,
     * otherwise the Files screen reports a number the picker cannot show.
     */
    private fun baseSelection(): String {
        val parts = mutableListOf("${MediaStore.MediaColumns.SIZE} > 0")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            parts.add("${MediaStore.MediaColumns.IS_PENDING} = 0")
        }
        return parts.joinToString(" AND ")
    }

    private fun count(
        context: Context,
        collection: Uri,
        selection: String?,
        selectionArgs: Array<String>?,
    ): Int {
        return try {
            context.contentResolver.query(
                collection,
                arrayOf(MediaStore.MediaColumns._ID),
                selection,
                selectionArgs,
                null,
            )?.use { cursor -> cursor.count } ?: 0
        } catch (_: Exception) {
            0
        }
    }

    /**
     * Counts documents in one query.
     *
     * `MediaStore.Files` exposes every indexed file regardless of type, so the
     * document mimes are filtered in SQL rather than by scanning directories.
     */
    private fun countDocuments(context: Context): Int {
        val placeholders = documentMimes.joinToString(",") { "?" }
        val selection = buildString {
            append(MediaStore.MediaColumns.MIME_TYPE).append(" IN (").append(placeholders).append(")")
            append(" AND ").append(baseSelection())
        }
        return count(context, MediaStore.Files.getContentUri("external"), selection, documentMimes)
    }

    private fun queryDocuments(context: Context, limit: Int): List<Map<String, Any?>> {
        val placeholders = documentMimes.joinToString(",") { "?" }
        val selection = buildString {
            append(MediaStore.MediaColumns.MIME_TYPE).append(" IN (").append(placeholders).append(")")
            append(" AND ").append(baseSelection())
        }
        return queryCollection(
            context,
            MediaStore.Files.getContentUri("external"),
            isVideo = false,
            limit = limit,
            selection = selection,
            selectionArgs = documentMimes,
        )
    }

    /**
     * Reads one MediaStore collection.
     *
     * `IS_PENDING` is filtered out because in-flight downloads are not readable
     * yet, and a zero-length row is skipped so the picker cannot offer a file
     * that has no bytes. Sorting happens in SQL (`DATE_ADDED DESC`) so the
     * newest items are the ones that survive the row limit, and no second pass
     * over thousands of rows is needed in Dart.
     */
    private fun queryCollection(
        context: Context,
        collection: Uri,
        isVideo: Boolean,
        limit: Int,
        selection: String = baseSelection(),
        selectionArgs: Array<String>? = null,
    ): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()

        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_ADDED,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.DATA,
        )

        try {
            context.contentResolver.query(
                collection,
                projection,
                selection,
                selectionArgs,
                "${MediaStore.MediaColumns.DATE_ADDED} DESC",
            )?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
                val dateCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_ADDED)
                val mimeCol = cursor.getColumnIndex(MediaStore.MediaColumns.MIME_TYPE)
                val dataCol = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)

                while (cursor.moveToNext() && out.size < minOf(limit, MAX_ITEMS)) {
                    val size = cursor.getLong(sizeCol)
                    if (size <= 0L) continue

                    val id = cursor.getLong(idCol)
                    val name = cursor.getString(nameCol) ?: continue
                    // DATE_ADDED is seconds since epoch, not milliseconds.
                    val addedSeconds = cursor.getLong(dateCol)

                    // The real filesystem path is what the Dart server streams
                    // from. It is still populated by MediaStore on every
                    // supported release; the content:// URI is the fallback.
                    val dataPath = if (dataCol >= 0) cursor.getString(dataCol) else null

                    out.add(
                        mapOf(
                            "name" to name,
                            "uri" to ContentUris.withAppendedId(collection, id).toString(),
                            "path" to dataPath,
                            "size" to size.toString(),
                            "modified" to (addedSeconds * 1000L).toString(),
                            "mime" to (if (mimeCol >= 0) cursor.getString(mimeCol) else null),
                            "video" to isVideo,
                        )
                    )
                }
            }
        } catch (_: Exception) {
            // A missing or denied provider yields an empty category rather than
            // failing the whole listing.
        }

        return out
    }
}
