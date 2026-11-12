package org.vrpassthroughplayer.plugin

import android.content.Context
import java.io.File
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import org.json.JSONObject

internal object MpvNative {
    init {
        System.loadLibrary("quest_mpv")
    }

    @JvmStatic external fun probe(context: Context, path: String): String

    @JvmStatic
    external fun probeGpu(
        context: Context,
        path: String,
        hardware: Boolean,
        width: Int,
        height: Int,
    ): String
}

/** MPV playback diagnostics, entirely absent from Release. */
internal object MpvDiagnostics {
    private val busy = AtomicBoolean(false)
    private val sequence = AtomicInteger(0)
    private val worker =
        ThreadPoolExecutor(
            1,
            1,
            0,
            TimeUnit.MILLISECONDS,
            ArrayBlockingQueue(1),
            { task -> Thread(task, "QuestMpvCoreProbe") },
            ThreadPoolExecutor.AbortPolicy(),
        )

    fun requestExternal(context: Context, requestKey: String): Int {
        if (!busy.compareAndSet(false, true)) return -1
        val id = sequence.incrementAndGet()
        try {
            worker.execute {
                val uri =
                    android.net.Uri.parse(
                        "content://org.vrpassthroughplayer.urifixture.documents/document/clip"
                    )
                val report = JSONObject()
                var opened = false
                var closed = true
                var permission = false
                try {
                    permission =
                        context.checkUriPermission(
                            uri,
                            android.os.Process.myPid(),
                            android.os.Process.myUid(),
                            android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION,
                        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
                    val descriptor =
                        context.contentResolver.openFileDescriptor(uri, "r")
                            ?: error("External document descriptor unavailable")
                    opened = true
                    closed = false
                    try {
                        // Hold the granted FD until synchronous native decoder/GPU teardown.
                        val native =
                            JSONObject(
                                MpvNative.probeGpu(
                                    context,
                                    "fd://${descriptor.fd}",
                                    true,
                                    1280,
                                    640,
                                )
                            )
                        native.keys().forEach { key -> report.put(key, native.get(key)) }
                        report.put("descriptor_bytes", descriptor.statSize)
                    } finally {
                        descriptor.close()
                        closed = true
                    }
                } catch (error: SecurityException) {
                    report
                        .put("state", "failed")
                        .put("error_type", "permission_denied")
                        .put("detail", error.toString())
                } catch (error: Exception) {
                    report
                        .put("state", "failed")
                        .put("error_type", if (opened) "native_decode_failed" else "open_failed")
                        .put("detail", error.toString())
                } finally {
                    report
                        .put("request_id", id)
                        .put("request_key", requestKey)
                        .put("diagnostic_process", DiagnosticRequests.processId)
                        .put("uri", uri.toString())
                        .put("client_uid", android.os.Process.myUid())
                        .put("permission_granted", permission)
                        .put("descriptor_opened", opened)
                        .put("descriptor_closed", closed)
                        .put("fixture", "mp03_frame_identity")
                        .put("probe_kind", "external_uri")
                        .put(
                            "scope",
                            "Cross-UID read grant and native FD decode only; picker, Godot/XR and device reboot unverified",
                        )
                    try {
                        val directory =
                            File(context.filesDir, "diagnostics").apply {
                                check(mkdirs() || isDirectory)
                            }
                        val temporary = File.createTempFile("mpv-uri-", ".tmp", directory)
                        try {
                            temporary.writeText(report.toString())
                            check(temporary.renameTo(File(directory, "mpv_uri_$id.json")))
                        } finally {
                            temporary.delete()
                        }
                    } finally {
                        busy.set(false)
                    }
                }
            }
        } catch (_: Exception) {
            busy.set(false)
            return -1
        }
        return id
    }

    fun request(
        context: Context,
        fixture: String,
        gpu: Boolean = false,
        hardware: Boolean = false,
        requestKey: String,
    ): Int {
        require(fixture in listOf("c03_sbs_grid", "c04_alpha_f180", "c04_independent_alpha"))
        if (!busy.compareAndSet(false, true)) return -1
        val id = sequence.incrementAndGet()
        try {
            worker.execute {
                var report = JSONObject()
                try {
                    val fixtures =
                        File(context.filesDir, "fixtures").apply { check(mkdirs() || isDirectory) }
                    val input = File(fixtures, "mpv_$fixture.mp4")
                    context.assets.open("media/$fixture.mp4").use { src ->
                        input.outputStream().use { src.copyTo(it) }
                    }
                    report =
                        JSONObject(
                            if (gpu)
                                MpvNative.probeGpu(
                                    context,
                                    input.absolutePath,
                                    hardware,
                                    if (fixture == "c03_sbs_grid") 1920 else 1280,
                                    if (fixture == "c03_sbs_grid") 1080 else 640,
                                )
                            else MpvNative.probe(context, input.absolutePath)
                        )
                } catch (error: Throwable) {
                    report
                        .put("state", "failed")
                        .put("detail", error.javaClass.name + ": " + error.message)
                } finally {
                    report
                        .put("request_id", id)
                        .put("request_key", requestKey)
                        .put("diagnostic_process", DiagnosticRequests.processId)
                        .put("fixture", fixture)
                        .put("probe_kind", if (gpu) "gpu" else "core")
                        .put("requested_hardware", hardware)
                    try {
                        val directory =
                            File(context.filesDir, "diagnostics").apply {
                                check(mkdirs() || isDirectory)
                            }
                        val tmp = File.createTempFile("mpv-core-", ".tmp", directory)
                        val kind = if (gpu) "gpu" else "core"
                        try {
                            tmp.writeText(report.toString())
                            check(tmp.renameTo(File(directory, "mpv_" + kind + "_$id.json")))
                        } finally {
                            tmp.delete()
                        }
                    } finally {
                        busy.set(false)
                    }
                }
            }
        } catch (error: Exception) {
            busy.set(false)
            return -1
        }
        return id
    }
}
