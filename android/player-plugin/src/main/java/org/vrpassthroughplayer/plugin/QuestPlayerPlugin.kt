package org.vrpassthroughplayer.plugin

import android.content.Intent
import android.content.IntentFilter
import android.opengl.EGL14
import android.opengl.GLES30
import android.os.BatteryManager
import android.os.Handler
import android.os.Looper
import android.text.format.DateFormat
import android.util.Log
import java.io.File
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import org.godotengine.godot.Godot
import org.godotengine.godot.GodotHost
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONArray
import org.json.JSONObject

class QuestPlayerPlugin(godot: Godot) : GodotPlugin(godot) {
    private val closed = AtomicBoolean(false)
    private var presenceMonitor: HeadsetPresenceMonitor? = null
    private var nativeWearerPresent = true // Main thread only.
    private var openxrWearerPresent = true // Main thread only.
    @Volatile private var wearerPresent = true
    @Volatile private var appForeground = true
    private val thumbnails =
        LocalVideoThumbnails(
            {
                !closed.get() && appForeground && wearerPresent && !mpv.hasActiveVideo()
            },
            { id, result -> if (!closed.get()) emitSignal("media_list", id, result) },
        )

    @UsedByGodot fun is_headset_present(): Boolean = wearerPresent

    @UsedByGodot
    fun set_openxr_presence(present: Boolean) {
        runOnHostThread {
            if (!closed.get()) {
                openxrWearerPresent = present
                updateWearerPresence("OpenXR")
            }
        }
    }

    private fun updateWearerPresence(source: String) {
        val present = nativeWearerPresent && openxrWearerPresent
        if (present == wearerPresent) return
        wearerPresent = present
        mpv.setWearerPresent(present)
        if (!present) thumbnails.cancel()
        if (signalsReady) emitSignal("headset_presence_changed", present, source)
    }

    @UsedByGodot
    fun media_local_thumbnail(uri: String): Int {
        if (closed.get() || LocalThumbnailPolicy.path(uri) == null) return -1
        val id = sources.nextId()
        thumbnails.request(id, uri)
        return id
    }

    @UsedByGodot
    fun media_local_thumbnail_cancel() {
        thumbnails.cancel()
    }

    private val updateChecks = UpdateCheckRequests { id, result ->
        if (!closed.get()) emitSignal("update_check_ready", id, result)
    }

    @UsedByGodot
    fun request_update_check(version: String): Int =
        if (closed.get()) -1 else updateChecks.request(version)

    private val releasePageOpener =
        ReleasePageOpener(
            active = { !closed.get() },
            post = { operation ->
                check(activity != null) { "Activity unavailable" }
                runOnHostThread { operation() }
            },
            launch = { url ->
                val host = activity ?: error("Activity unavailable")
                host.startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url)))
            },
            report = { id, tag, opened -> emitSignal("update_release_opened", id, tag, opened) },
        )

    @UsedByGodot fun open_update_release(tag: String): Int = releasePageOpener.open(tag)

    @Volatile private var signalsReady = false
    private val requestId = AtomicInteger(0)
    private val probe =
        ThreadPoolExecutor(
            1,
            1,
            0,
            TimeUnit.MILLISECONDS,
            ArrayBlockingQueue(1),
            { task -> Thread(task, "QuestCapabilityProbe") },
            ThreadPoolExecutor.DiscardOldestPolicy(),
        )

    @Volatile private var graphicsSnapshot = "{\"observed\":false}"
    private val picker =
        LocalVideoPicker({ activity }) { json ->
            if (!closed.get()) emitSignal("local_video_selected", json)
        }
    private val subtitlePicker =
        LocalVideoPicker({ activity }, "*/*", 0x6650) { json ->
            if (!closed.get()) emitSignal("local_subtitle_selected", json)
        }
    private val localAccess =
        LocalVideoAccess({ activity?.applicationContext }) { id, json ->
            if (!closed.get()) emitSignal("local_video_access", id, json)
        }

    // queueEvent runs on the GL thread, but Godot can have released its EGL context
    // there. Native GL work must wait for an actual draw callback with a current context.
    private val controlledRenderTasks = ArrayBlockingQueue<Runnable>(16)
    private val sources =
        MediaSources({ activity }) { id, json ->
            if (!closed.get())
                emitSignal(
                    "media_list",
                    id,
                    json,
                )
        }
    private val accounts = AccountManager { activity }
    private val mpv =
        MpvVideoBridge(
            { activity?.applicationContext },
            {
                check(controlledRenderTasks.offer(it)) { "Player render task capacity exhausted" }
            },
            { name, id, json -> if (!closed.get()) emitSignal(name, id, json) },
            sources::playable,
            sources::sidecarAudio,
            sources::releaseMediaStream,
            sources::sidecarSubtitles,
            sources::resolveShortcut,
        )

    init {
        DiagnosticRequests.attach(this)
    }

    override fun getPluginName() = "QuestPlayer"

    /** Use the engine host's process restart/termination path so XR is created afresh. */
    @UsedByGodot
    fun finish_app(restart: Boolean) {
        if (!closed.get())
            runOnHostThread {
                val host = activity as? GodotHost ?: return@runOnHostThread
                if (restart) host.onGodotRestartRequested(godot) else host.onGodotForceQuit(godot)
            }
    }

    @UsedByGodot
    fun set_ui_language(choice: String) {
        activity?.applicationContext?.let { UiLanguage.setChoice(it, choice) }
    }

    override fun getPluginSignals() =
        setOf(
            SignalInfo(
                "update_release_opened",
                Int::class.javaObjectType,
                String::class.java,
                Boolean::class.javaObjectType,
            ),
            SignalInfo("update_check_ready", Int::class.javaObjectType, String::class.java),
            SignalInfo("diagnostic_log_saved", Int::class.javaObjectType, String::class.java),
            SignalInfo("capabilities_ready", Int::class.javaObjectType, String::class.java),
            SignalInfo("android_lifecycle", String::class.java),
            SignalInfo(
                "headset_presence_changed",
                Boolean::class.javaObjectType,
                String::class.java,
            ),
            SignalInfo("media_list", Int::class.javaObjectType, String::class.java),
            SignalInfo("local_video_selected", String::class.java),
            SignalInfo("local_subtitle_selected", String::class.java),
            SignalInfo("mpv_subtitle_import", Int::class.javaObjectType, String::class.java),
            SignalInfo("local_video_access", Int::class.javaObjectType, String::class.java),
            SignalInfo("mpv_state", Int::class.javaObjectType, String::class.java),
            SignalInfo("mpv_pair_available", Int::class.javaObjectType, String::class.java),
            SignalInfo("mpv_error", Int::class.javaObjectType, String::class.java),
            SignalInfo("mpv_detach", Int::class.javaObjectType, String::class.java),
            SignalInfo("mpv_released", Int::class.javaObjectType, String::class.java),
            SignalInfo("mpv_debug_command", Int::class.javaObjectType, String::class.java),
            SignalInfo("mpv_pixel_mask", Int::class.javaObjectType, String::class.java),
            SignalInfo("mpv_frozen_pair", Int::class.javaObjectType, String::class.java),
        )

    @UsedByGodot
    fun pick_local_video(): Int {
        if (closed.get()) return -1
        val id = requestId.incrementAndGet()
        runOnHostThread { if (!closed.get()) picker.open(id) }
        return id
    }

    @UsedByGodot
    fun pick_local_subtitle(): Int {
        if (closed.get()) return -1
        val id = requestId.incrementAndGet()
        runOnHostThread { if (!closed.get()) subtitlePicker.open(id) }
        return id
    }

    @UsedByGodot
    fun cancel_local_subtitle_pick(id: Int) {
        if (!closed.get()) runOnHostThread { subtitlePicker.cancel(id) }
    }

    @UsedByGodot
    fun set_mpv_sync(id: Int, subtitleMs: Int, audioMs: Int): Boolean =
        !closed.get() && mpv.setSync(id, subtitleMs, audioMs)

    @UsedByGodot
    fun record_diagnostic_event(event: String, json: String): Boolean = runCatching {
        require(!closed.get() && event.length <= 64 && json.length <= 16384)
        val app = activity?.applicationContext ?: return false
        DiagnosticLogs.record(File(app.filesDir, "diagnostics"), event, json)
        true
    }
        .getOrDefault(false)

    @UsedByGodot
    fun diagnostic_previous_available(): Boolean =
        activity?.applicationContext?.let {
            File(it.filesDir, "diagnostics/crash/last-report.txt").isFile
        } ?: false

    @UsedByGodot
    fun save_diagnostic_log(): Int {
        val app = activity?.applicationContext ?: return -1
        val id = requestId.incrementAndGet()
        return if (
            !closed.get() &&
                DiagnosticLogs.request(app) { result ->
                    if (!closed.get()) emitSignal("diagnostic_log_saved", id, result.toString())
                }
        )
            id
        else -1
    }

    @UsedByGodot
    fun external_playback_belongs_to(uri: String, root: String, uuid: String): Boolean =
        uri.length <= 8192 &&
            root.length <= 8192 &&
            uuid.length <= 64 &&
            ExternalPlaybackPending.leases.belongsTo(uri, root, uuid)

    @UsedByGodot
    fun external_playback_release(uri: String) {
        if (uri.startsWith("externalvideo://")) ExternalPlaybackPending.leases.release(uri)
    }

    @UsedByGodot
    fun external_playback_poll(): String =
        if (!closed.get() && signalsReady) ExternalPlaybackPending.poll() else "{}"

    @UsedByGodot
    fun subtitle_candidates(uri: String): Int =
        if (closed.get() || uri.length > 8192) -1 else sources.subtitleCandidates(uri)

    @UsedByGodot
    fun media_server_playback(json: String): Boolean = !closed.get() && sources.reportPlayback(json)

    @UsedByGodot
    fun configure_subtitle_encodings(uri: String, json: String): Boolean =
        !closed.get() && mpv.subtitleEncodings(uri, json)

    @UsedByGodot
    fun add_mpv_subtitle(id: Int, uri: String): Boolean = !closed.get() && mpv.addSubtitle(id, uri)

    @UsedByGodot
    fun cancel_local_video_pick(id: Int) {
        if (!closed.get()) runOnHostThread { picker.cancel(id) }
    }

    @UsedByGodot
    fun request_local_video_access(uri: String): Int {
        if (closed.get()) return -1
        val id = requestId.incrementAndGet()
        return if (localAccess.request(id, uri)) id else -1
    }

    @UsedByGodot
    fun cancel_local_video_access(id: Int) {
        localAccess.cancel(id)
    }

    /**
     * Headset battery and clock style: {"level": 0..100 or -1, "charging", "plugged", "clock24"}.
     */
    @UsedByGodot
    fun device_status(): String {
        val host = activity ?: return "{}"
        val battery = host.getSystemService(BatteryManager::class.java)
        // Read the latest sticky snapshot without subscribing a receiver or requesting permissions.
        val snapshot = runCatching {
            host.registerReceiver(
                null,
                IntentFilter(Intent.ACTION_BATTERY_CHANGED),
            )
        }
            .getOrNull()
        val state =
            DeviceBatteryStatus.resolve(
                snapshot?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1,
                snapshot?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1,
                snapshot?.getIntExtra(
                    BatteryManager.EXTRA_STATUS,
                    BatteryManager.BATTERY_STATUS_UNKNOWN,
                ) ?: BatteryManager.BATTERY_STATUS_UNKNOWN,
                snapshot?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1) ?: -1,
                runCatching {
                        battery?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
                    }
                    .getOrDefault(-1),
                runCatching { battery?.isCharging ?: false }.getOrDefault(false),
            )
        return JSONObject()
            .put("level", state.level)
            .put("charging", state.charging)
            .put("plugged", state.plugged)
            .put("clock24", DateFormat.is24HourFormat(host))
            .toString()
    }

    @UsedByGodot fun mpv_supported(): Boolean = !closed.get() && mpv.supported()

    @UsedByGodot
    fun set_mpv_output_width(width: Int) {
        if (width in 0..8192) mpv.outputWidthCap = width
    }

    // Library sources: each returns a request id; the result arrives as media_list(id, json).
    /** Headset storage: path "" lists the volumes, otherwise one folder's subfolders and videos. */
    @UsedByGodot
    fun media_local_browse(path: String): Int {
        if (closed.get()) return -1
        val id = sources.nextId()
        runOnHostThread { if (!closed.get()) sources.browseLocal(id, path) }
        return id
    }

    @UsedByGodot
    fun media_local_storage_settings(path: String): Int {
        if (closed.get()) return -1
        val id = sources.nextId()
        runOnHostThread { if (!closed.get()) sources.openLocalEjectSettings(id, path) }
        return id
    }

    @UsedByGodot
    fun media_file_management_enabled(enabled: Boolean) {
        if (!closed.get()) sources.setFileManagement(enabled)
    }

    @UsedByGodot
    fun media_file_delete(json: String): Int = if (closed.get()) -1 else sources.deleteFile(json)

    @UsedByGodot
    fun media_file_rename_prepare(json: String): Int =
        if (closed.get()) -1 else sources.renameFile(json, true)

    @UsedByGodot
    fun media_file_rename(json: String): Int =
        if (closed.get()) -1 else sources.renameFile(json, false)

    @UsedByGodot
    fun media_file_delete_prepare(json: String): Int =
        if (closed.get()) -1 else sources.deleteFile(json, prepare = true)

    @UsedByGodot
    fun media_file_delete_status(json: String): Int =
        if (closed.get()) -1 else sources.deleteFile(json, true)

    @UsedByGodot
    fun account_open(kind: String, provider: String, id: String, json: String): Int =
        if (closed.get()) -1 else accounts.open(kind, provider, id, json)

    @UsedByGodot
    fun account_list(kind: String): String = if (closed.get()) "null" else accounts.accounts(kind)

    @UsedByGodot
    fun account_snapshot(id: Int): String = if (closed.get()) "{}" else accounts.snapshot(id)

    @UsedByGodot
    fun account_input(id: Int, field: String, action: String, text: String) {
        if (!closed.get()) accounts.input(id, field, action, text)
    }

    @UsedByGodot
    fun account_action(id: Int, action: String, json: String) {
        if (!closed.get()) accounts.action(id, action, json)
    }

    @UsedByGodot
    fun account_cancel(id: Int) {
        accounts.cancel(id)
    }

    @UsedByGodot
    fun license_text(id: String): String =
        activity?.applicationContext?.let { LicenseCatalog.text(it, id) } ?: ""

    @UsedByGodot
    fun media_server_request(json: String): Int =
        if (closed.get()) -1 else sources.serverRequest(json)

    @UsedByGodot
    fun media_server_cancel(id: Int) {
        sources.serverCancel(id)
    }

    /**
     * Opens the system "All files access" page (folders beyond media ones, files beside videos).
     */
    @UsedByGodot
    fun media_local_grant_all_files() {
        if (!closed.get()) runOnHostThread { sources.grantAllFiles() }
    }

    @UsedByGodot fun media_dlna_discover(): Int = if (closed.get()) -1 else sources.dlnaDiscover()

    @UsedByGodot fun media_dlna_servers(): Int = if (closed.get()) -1 else sources.dlnaServers()

    @UsedByGodot
    fun media_dlna_save(json: String): Int = if (closed.get()) -1 else sources.dlnaSave(json)

    @UsedByGodot
    fun media_dlna_remove(id: String): Int = if (closed.get()) -1 else sources.dlnaRemove(id)

    @UsedByGodot
    fun media_dlna_browse(server: String, objectId: String): Int =
        if (closed.get()) -1 else sources.dlnaBrowse(server, objectId)

    @UsedByGodot fun media_smb_servers(): Int = if (closed.get()) -1 else sources.smbServers()

    @UsedByGodot fun media_smb_discover(): Int = if (closed.get()) -1 else sources.smbDiscover()

    /** {id?, name, host, domain, user, password}; an empty password keeps the saved one. */
    @UsedByGodot
    fun media_smb_save(json: String): Int = if (closed.get()) -1 else sources.smbSave(json)

    @UsedByGodot
    fun media_smb_remove(id: String): Int = if (closed.get()) -1 else sources.smbRemove(id)

    @UsedByGodot
    fun media_smb_browse(server: String, path: String): Int =
        if (closed.get()) -1 else sources.smbBrowse(server, path)

    /**
     * topBottom: a stereo source with the views above each other (top = left eye) instead of side
     * by side.
     */
    @UsedByGodot
    fun open_mpv_video(
        uri: String,
        startMs: Int,
        stereo: Boolean,
        profile: String,
        vulkan: Boolean,
        topBottom: Boolean,
        exactSeek: Boolean,
    ): Int =
        if (closed.get()) -1
        else {
            thumbnails.cancel()
            mpv.open(
                uri,
                startMs,
                stereo,
                profile,
                vulkan,
                topBottom = topBottom,
                exactSeek = exactSeek,
            )
        }

    @UsedByGodot
    fun revise_mpv_video(
        id: Int,
        stereo: Boolean,
        profile: String,
        positionMs: Int,
        topBottom: Boolean,
        exactSeek: Boolean,
    ): Int =
        if (closed.get()) -1
        else
            mpv.revise(
                id,
                stereo,
                profile,
                positionMs,
                topBottom,
                exactSeek,
            )

    @UsedByGodot
    fun set_mpv_playing(id: Int, playing: Boolean) {
        if (!closed.get()) mpv.setPlaying(id, playing)
    }

    @UsedByGodot
    fun set_mpv_audio(id: Int, trackId: Int, volume: Double, muted: Boolean): Boolean =
        !closed.get() && mpv.setAudio(id, trackId, volume, muted)

    @UsedByGodot
    fun set_mpv_speed(id: Int, speed: Double): Boolean = !closed.get() && mpv.setSpeed(id, speed)

    @UsedByGodot
    fun set_mpv_subtitle(id: Int, trackId: Int): Boolean =
        !closed.get() && mpv.setSubtitle(id, trackId)

    @UsedByGodot
    fun set_mpv_secondary_subtitle(id: Int, trackId: Int): Boolean =
        !closed.get() && mpv.setSecondarySubtitle(id, trackId)

    @UsedByGodot
    fun get_mpv_subtitles(id: Int, afterSequence: Long): String =
        if (closed.get()) "" else mpv.subtitles(id, afterSequence)

    @UsedByGodot
    fun claim_mpv_pair(id: Int, token: Long): String =
        if (closed.get()) "" else mpv.claim(id, token)

    @UsedByGodot
    fun acknowledge_mpv_pair(id: Int, token: Long): Boolean =
        !closed.get() && mpv.acknowledge(id, token)

    @UsedByGodot fun detach_mpv_pair(id: Int, token: Long): Boolean = mpv.detach(id, token)

    @UsedByGodot
    fun freeze_mpv_pair(id: Int, token: Long, request: Int): Boolean =
        !closed.get() && mpv.freeze(id, token, request)

    @UsedByGodot
    fun release_mpv_frozen_frame(id: Long) {
        mpv.releaseFrozen(id)
    }

    @UsedByGodot
    fun retain_mpv_frozen_frame(id: Long): Boolean = !closed.get() && mpv.retainFrozen(id)

    @UsedByGodot
    fun pin_mpv_pair(id: Int, token: Long): Boolean = !closed.get() && mpv.pinPair(id, token)

    @UsedByGodot fun release_mpv_pair_pin(id: Int, token: Long): Boolean = mpv.unpinPair(id, token)

    @UsedByGodot
    fun close_mpv_video(id: Int) {
        mpv.close(id)
    }

    @UsedByGodot
    fun request_mpv_pixel_mask(request: Int, id: Int, token: Long): Boolean =
        !closed.get() && mpv.requestPixelMask(request, id, token)

    @UsedByGodot
    fun release_mpv_pixel_pin(id: Int, token: Long): Boolean = mpv.unpinPixelPair(id, token)

    internal fun requestMpvPlayerCommand(json: String): Int {
        if (closed.get()) return -1
        val id = requestId.incrementAndGet()
        emitSignal("mpv_debug_command", id, json)
        return id
    }

    @UsedByGodot
    fun save_mpv_player_report(id: Int, json: String): String {
        if (id <= 0) return "ERROR:INVALID_REQUEST"
        return try {
            JSONObject(json)
            val host = activity?.applicationContext ?: return "ERROR:ACTIVITY_UNAVAILABLE"
            val directory = File(host.filesDir, "diagnostics").apply { mkdirs() }
            val temporary = File.createTempFile("mpv-player-", ".tmp", directory)
            try {
                temporary.writeText(json)
                check(temporary.renameTo(File(directory, "mpv_player_$id.json")))
            } finally {
                temporary.delete()
            }
            "mpv_player_$id.json"
        } catch (failure: Exception) {
            "ERROR:" + failure.javaClass.simpleName
        }
    }

    override fun onMainRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String?>?,
        grantResults: IntArray?,
    ) {
        if (!closed.get())
            sources.onPermissionResult(
                requestCode,
                grantResults != null &&
                    grantResults.isNotEmpty() &&
                    grantResults.all { it == android.content.pm.PackageManager.PERMISSION_GRANTED },
            )
    }

    override fun onMainActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!closed.get()) {
            picker.result(requestCode, resultCode, data)
            subtitlePicker.result(
                requestCode,
                resultCode,
                data,
            )
        }
    }

    override fun onGLDrawFrame(gl: GL10?) {
        if (EGL14.eglGetCurrentContext() == EGL14.EGL_NO_CONTEXT) return
        repeat(16) { controlledRenderTasks.poll()?.run() ?: return@repeat }
        if (!closed.get()) {
            mpv.draw()
            XrUiSurfaceBridge.draw()
        }
    }

    @UsedByGodot
    fun request_capabilities(): Int {
        if (closed.get()) return -1
        val id = requestId.incrementAndGet()
        try {
            probe.execute {
                if (closed.get() || id != requestId.get()) return@execute
                val result =
                    try {
                        DeviceCapabilities.collect(graphicsSnapshot)
                    } catch (error: Exception) {
                        JSONObject()
                            .put(
                                "probe_error",
                                error.javaClass.simpleName + ": " + (error.message ?: ""),
                            )
                    }
                if (!closed.get() && id == requestId.get()) {
                    emitSignal("capabilities_ready", id, result.toString())
                }
            }
        } catch (_: RejectedExecutionException) {
            return -1
        }
        return id
    }

    @UsedByGodot
    fun save_capability_report(json: String): String {
        val host = activity ?: return "ERROR:ACTIVITY_UNAVAILABLE"
        return try {
            JSONObject(json)
            val directory = File(host.filesDir, "diagnostics")
            if (!directory.isDirectory && !directory.mkdirs()) return "ERROR:DIRECTORY_UNAVAILABLE"
            val target = File(directory, "capabilities.json")
            val temporary = File.createTempFile("capabilities-", ".tmp", directory)
            try {
                temporary.writeText(json, Charsets.UTF_8)
                if (!temporary.renameTo(target)) return "ERROR:REPORT_RENAME_FAILED"
            } finally {
                if (temporary.exists()) temporary.delete()
            }
            target.absolutePath
        } catch (error: Exception) {
            Log.e("VRPassthroughPlayer", "Capability report could not be saved", error)
            "ERROR:" + error.javaClass.simpleName
        }
    }

    override fun onGLSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        XrUiSurfaceBridge.contextCreated()
        mpv.contextCreated()
        val report =
            JSONObject()
                .put("observed", true)
                .put("vendor", GLES30.glGetString(GLES30.GL_VENDOR))
                .put("renderer", GLES30.glGetString(GLES30.GL_RENDERER))
                .put("version", GLES30.glGetString(GLES30.GL_VERSION))
        val count = IntArray(1)
        GLES30.glGetIntegerv(GLES30.GL_NUM_EXTENSIONS, count, 0)
        val extensions = JSONArray()
        for (index in 0 until count[0]) extensions.put(
            GLES30.glGetStringi(
                GLES30.GL_EXTENSIONS,
                index,
            )
        )
        graphicsSnapshot = report.put("extensions", extensions).toString()
        Log.i("VRPassthroughPlayer", "GLES context observed")
    }

    // Android can resume before Godot registers the plugin's native signals.
    override fun onGodotSetupCompleted() {
        activity?.applicationContext?.let { CrashRecords.start(it) }
        signalsReady = true
        activity?.runOnUiThread {
            if (!closed.get() && presenceMonitor == null) {
                activity?.applicationContext?.let { context ->
                    presenceMonitor =
                        HeadsetPresenceMonitor(context) { present, source ->
                                if (!closed.get()) {
                                    nativeWearerPresent = present
                                    updateWearerPresence(source)
                                }
                            }
                            .also { it.start() }
                }
            }
        }
    }

    override fun onMainPause() {
        appForeground = false
        thumbnails.cancel()
        if (!closed.get()) {
            CrashRecords.foreground(false)
            mpv.pause()
            if (signalsReady)
                emitSignal(
                    "android_lifecycle",
                    "pause",
                )
        }
    }

    override fun onMainResume() {
        appForeground = true
        if (!closed.get()) {
            CrashRecords.foreground(true)
            mpv.resume()
            if (signalsReady) {
                sources.refreshLocalStorage()
                emitSignal("android_lifecycle", "resume")
            }
        }
    }

    override fun onMainDestroy() {
        close()
    }

    override fun onGodotTerminating() {
        close()
    }

    private fun close() {
        if (closed.compareAndSet(false, true)) {
            thumbnails.close()
            Handler(Looper.getMainLooper()).post {
                presenceMonitor?.close()
                presenceMonitor = null
            }
            updateChecks.close()
            CrashRecords.cleanExit()
            accounts.close()
            picker.close()
            subtitlePicker.close()
            localAccess.close()
            probe.shutdownNow()
            mpv.shutdown()
            sources.close()
        }
    }
}
