package com.m5dev.libreshare

import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Enumerates device media through the MediaStore content providers.
 *
 * This exists because walking the filesystem directly does not work on modern
 * Android: scoped storage (API 29+) hides `/storage/emulated/0` from `dart:io`,
 * so a directory walk returns nothing and the picker shows "0 photos" even
 * when the permission is granted. MediaStore is the only supported way to see
 * the user's media.
 *
 * Each category is queried independently so one failing provider (a device
 * with no audio index, say) cannot empty the others. Documents are the
 * exception: MediaStore has no document collection worth reading, so they come
 * from a bounded scan of the public document directories.
 */
object MediaStoreHandler {

    private const val MAX_ITEMS = 5000

    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "libreshare-media-store").apply { isDaemon = true }
    }

    fun listMedia(context: Context, result: MethodChannel.Result) {
        val appContext = context.applicationContext
        worker.execute {
            try {
                val payload = collect(appContext)
                mainHandler.post { result.success(payload) }
            } catch (e: Throwable) {
                mainHandler.post { result.error("MEDIA_LIST_FAILED", e.message, null) }
            }
        }
    }

    private fun collect(context: Context): Map<String, List<Map<String, Any?>>> {
        return mapOf(
            "photos" to queryImages(context),
            "videos" to queryVideos(context),
            "music" to queryAudio(context),
            "documents" to scanDocuments(),
        )
    }

    private fun queryImages(context: Context): List<Map<String, Any?>> =
        queryCollection(context, MediaStore.Images.Media.EXTERNAL_CONTENT_URI, isVideo = false)

    private fun queryVideos(context: Context): List<Map<String, Any?>> =
        queryCollection(context, MediaStore.Video.Media.EXTERNAL_CONTENT_URI, isVideo = true)

    private fun queryAudio(context: Context): List<Map<String, Any?>> =
        queryCollection(context, MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, isVideo = false)

    /**
     * Reads one MediaStore collection.
     *
     * `IS_PENDING` is filtered out because in-flight downloads are not readable
     * yet, and a zero-length row is skipped so the picker cannot offer a file
     * that has no bytes. Sorting happens in SQL (`DATE_MODIFIED DESC`) to avoid
     * a second pass over thousands of rows in Dart.
     */
    private fun queryCollection(
        context: Context,
        collection: Uri,
        isVideo: Boolean,
    ): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()

        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.DATA,
        )

        val selection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            "${MediaStore.MediaColumns.IS_PENDING} = 0"
        } else {
            null
        }

        try {
            context.contentResolver.query(
                collection,
                projection,
                selection,
                null,
                "${MediaStore.MediaColumns.DATE_MODIFIED} DESC",
            )?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
                val dateCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
                val mimeCol = cursor.getColumnIndex(MediaStore.MediaColumns.MIME_TYPE)
                val dataCol = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)

                while (cursor.moveToNext() && out.size < MAX_ITEMS) {
                    val size = cursor.getLong(sizeCol)
                    if (size <= 0L) continue

                    val id = cursor.getLong(idCol)
                    val name = cursor.getString(nameCol) ?: continue
                    // DATE_MODIFIED is seconds since epoch, not milliseconds.
                    val modifiedSeconds = cursor.getLong(dateCol)

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
                            "modified" to (modifiedSeconds * 1000L).toString(),
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

    /**
     * Scans the public document directories for shareable files.
     *
     * MediaStore has no documents collection, and these paths stay readable
     * under scoped storage for the common cases (Downloads, Documents) when
     * storage access is granted.
     */
    private fun scanDocuments(): List<Map<String, Any?>> {
        val roots = listOfNotNull(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS),
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                ?.let { File(it, "LibreShare") },
        )

        val out = ArrayList<Map<String, Any?>>()
        val seen = HashSet<String>()

        for (root in roots) {
            if (!root.exists()) continue
            walk(root, 0, out, seen)
            if (out.size >= MAX_ITEMS) break
        }

        out.sortByDescending { (it["modified"] as? String)?.toLongOrNull() ?: 0L }
        return out
    }

    private fun walk(dir: File, depth: Int, out: MutableList<Map<String, Any?>>, seen: MutableSet<String>) {
        if (depth > 3 || out.size >= MAX_ITEMS) return

        val entries = try {
            dir.listFiles()
        } catch (_: Exception) {
            null
        } ?: return

        for (entry in entries) {
            if (out.size >= MAX_ITEMS) return
            if (entry.isDirectory) {
                walk(entry, depth + 1, out, seen)
                continue
            }
            if (!entry.isFile) continue

            val name = entry.name
            if (!isDocument(name)) continue
            if (!seen.add(entry.absolutePath)) continue

            val size = try {
                entry.length()
            } catch (_: Exception) {
                0L
            }
            if (size <= 0L) continue

            val modified = try {
                entry.lastModified()
            } catch (_: Exception) {
                0L
            }

            out.add(
                mapOf(
                    "name" to name,
                    "uri" to Uri.fromFile(entry).toString(),
                    "path" to entry.absolutePath,
                    "size" to size.toString(),
                    "modified" to modified.toString(),
                    "mime" to null,
                    "video" to false,
                )
            )
        }
    }

    private val documentExtensions = setOf(
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf",
        "csv", "zip", "rar", "7z", "tar", "gz", "json", "xml", "apk",
    )

    private fun isDocument(name: String): Boolean {
        val dot = name.lastIndexOf('.')
        if (dot <= 0 || dot == name.length - 1) return false
        return documentExtensions.contains(name.substring(dot + 1).lowercase())
    }
}
