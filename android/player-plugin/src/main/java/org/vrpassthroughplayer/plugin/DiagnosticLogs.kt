package org.vrpassthroughplayer.plugin

import android.content.ContentValues
import android.content.Context
import android.os.Environment
import android.provider.MediaStore
import org.json.JSONObject
import org.json.JSONArray
import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/** No network, logcat capture or automatic public export. */
internal object DiagnosticLogs {
    const val EVENT_BYTES = 256 * 1024
    const val EXPORT_CHARS = 128 * 1024
    private val worker = ThreadPoolExecutor(1, 1, 0, TimeUnit.MILLISECONDS, ArrayBlockingQueue(1),
        { Thread(it, "ImmivioLogExport").apply { isDaemon = true } })
    fun redact(value: String): String = PlaybackErrors.diagnostic(value)
    private val privateKey = Regex("(?i)^(?:.*token|.*password|.*authorization|.*cookie|.*signature|.*secret|.*account.*|username|user_name|user_id|user|email|api[_-]?key|key|pw|pwd|passwd)$")
    fun clean(value: Any?, depth: Int = 0, budget: IntArray = intArrayOf(256)): Any {
        if (depth > 6 || budget[0]-- <= 0) return "[bounded]"
        return when (value) {
            is JSONObject -> JSONObject().apply {
                value.keys().asSequence().take(32).forEach { key ->
                    put(redact(key).take(64), if (privateKey.matches(key)) "[redacted]" else clean(value.opt(key), depth + 1, budget))
                }
            }
            is JSONArray -> JSONArray().apply { for (i in 0 until minOf(32, value.length())) put(clean(value.opt(i), depth + 1, budget)) }
            is String -> redact(value).take(2048)
            is Number, is Boolean -> value
            else -> JSONObject.NULL
        }
    }
    @Synchronized fun record(directory: File, event: String, raw: String) {
        directory.mkdirs()
        val entry = clean(JSONObject(raw)) as JSONObject
        var text = entry.toString()
        if (text.toByteArray(Charsets.UTF_8).size > 8192) text = JSONObject().put("event", redact(event).take(64)).put("details", "[bounded]").toString()
        val file = File(directory, "events.jsonl")
        if (file.length() + text.toByteArray(Charsets.UTF_8).size + 1 > EVENT_BYTES) {
            java.nio.file.Files.move(file.toPath(), File(directory, "events.1.jsonl").toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING)
        }
        file.appendText(text + "\n", Charsets.UTF_8)
        CrashTrail.mark(redact(event).take(64), entry.optJSONObject("details")?.toString().orEmpty())
    }
    fun tail(file: File, limit: Int = EVENT_BYTES): String {
        if (!file.isFile) return ""
        return RandomAccessFile(file, "r").use { input ->
            val offset = maxOf(0L, input.length() - limit)
            input.seek(offset)
            val bytes = ByteArray(minOf(limit.toLong(), input.length() - offset).toInt()); input.readFully(bytes)
            val text = bytes.toString(Charsets.UTF_8)
            redact(if (offset > 0) text.substringAfter('\n', "") else text)
        }
    }
    fun compose(directory: File): String = redact(buildString {
        append("Immivio diagnostic log — saved by explicit user request\n\n")
        append("== Previous session ==\n").append(tail(File(directory, "crash/last-report.txt"), 128 * 1024))
        append("\n== Current steps ==\n").append(CrashTrail.current().joinToString("\n"))
        append("\n== Recent events ==\n").append(tail(File(directory, "events.1.jsonl"))).append(tail(File(directory, "events.jsonl")))
    }).take(EXPORT_CHARS)
    fun request(context: Context, report: (JSONObject) -> Unit): Boolean = try {
        worker.execute {
            val result = runCatching { save(context, compose(File(context.filesDir, "diagnostics"))) }
            report(JSONObject().put("ok", result.isSuccess).put("path", result.getOrDefault("")).put("error", if (result.isFailure) "Diagnostic log could not be saved" else ""))
        }; true
    } catch (_: java.util.concurrent.RejectedExecutionException) { false }
    private fun save(context: Context, text: String): String {
        val resolver = context.contentResolver
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val folder = Environment.DIRECTORY_DOWNLOADS + "/Immivio/logs/"
        val name = "immivio-log-${System.currentTimeMillis()}-${java.util.UUID.randomUUID().toString().take(8)}.txt"
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name); put(MediaStore.MediaColumns.MIME_TYPE, "text/plain")
            put(MediaStore.MediaColumns.RELATIVE_PATH, folder); put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values) ?: error("Download unavailable")
        try {
            resolver.openOutputStream(uri, "w")!!.use { it.write(redact(text).take(EXPORT_CHARS).toByteArray(Charsets.UTF_8)) }
            resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
            // Retain only our own five exports, never another app's or the user's unrelated files.
            runCatching {
                val selection = "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND ${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ? AND ${MediaStore.MediaColumns.OWNER_PACKAGE_NAME}=?"
                resolver.query(collection, arrayOf(MediaStore.MediaColumns._ID), selection,
                    arrayOf(folder, "immivio-log-%", context.packageName), MediaStore.MediaColumns.DATE_ADDED + " DESC, " + MediaStore.MediaColumns._ID + " DESC")?.use { cursor ->
                    var count = 0
                    while (count < 128 && cursor.moveToNext()) {
                        if (count++ >= 5) resolver.delete(android.content.ContentUris.withAppendedId(collection, cursor.getLong(0)), "${MediaStore.MediaColumns.OWNER_PACKAGE_NAME}=?", arrayOf(context.packageName))
                    }
                }
            }
            return folder + name
        } catch (error: Exception) { resolver.delete(uri, null, null); throw error }
    }
}
