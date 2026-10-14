package org.vrpassthroughplayer.plugin

import android.content.Context
import android.net.Uri
import android.opengl.EGL14
import android.opengl.EGLContext
import android.os.Handler
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import android.provider.OpenableColumns
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/** Production MPV -> immutable shared GPU color -> complete display pairs. Native MPV survives mode/layout/seek generations; old display claims
 * survive invalidation only until Godot detaches them after its last draw.
 */
internal class MpvVideoBridge(
    private val context: () -> Context?,
    private val render: (Runnable) -> Unit,
    private val emit: (String, Int, String) -> Unit,
    /** Library URI (smb://, http(s)://) -> MPV location; blocks, called on the worker. */
    private val resolveNetwork: (String) -> String = { it },
    /** Library URI -> extra M4A tracks beside the video (clone voice); blocks, called on the worker. */
    private val sidecarAudio: (String) -> List<SidecarAudio.Track> = { emptyList() },
    private val releaseNetwork: (String) -> Unit = {},
    private val sidecarSubtitles: (String) -> List<SidecarSubtitles.Track> = { emptyList() },
) {
    private val worker = PlaybackWorkers.video
    private val gate = MediaSessionGate()
    private val sessions = ConcurrentHashMap<Int, Session>()
    private val hosts = ConcurrentHashMap.newKeySet<PlaybackHost>()

    @Volatile
    private var foreground = true

    @Volatile
    private var stopped = false
    private val freezePending = AtomicBoolean(false)
    private val frozenFrames = ConcurrentHashMap<Long, AtomicInteger>()

    @Volatile
    private var debugNormalFastPath = true
    internal fun debugNormalFramePath(enabled: Boolean) {
        if (BuildConfig.DEBUG) debugNormalFastPath = enabled
    }

    @Volatile
    private var debugFrameCapOverride = -1

    /** Debug cadence verification only: -1 keeps the mode default. */
    internal fun debugFrameCap(fps: Int) {
        if (BuildConfig.DEBUG) debugFrameCapOverride = fps
    }

    @Volatile
    private var debugBorrowDisabled = false

    /** Debug A/B only: copy every captured 8K color instead of holding the MPV slot. */
    internal fun debugBorrowColor(enabled: Boolean) {
        if (BuildConfig.DEBUG) debugBorrowDisabled = !enabled
    }

    /** Debug A/B only: MPV renders an 8K RGBA copy instead of handing over the decoder's image. */
    private var audioFocus: MpvAudioFocus? = null // worker only

    @Volatile
    private var audioFocusState = "none"
    private val lifecyclePauses = AtomicInteger(0)
    private val audioFocusInterruptions = AtomicInteger(0)

    /** Current sessions display source media; legacy effect fields stay false until contract migration. */
    private class Session(
        val scope: MediaSessionGate.Scope,
        val host: PlaybackHost,
        private val requestedStereo: Boolean,
        val profile: String,
        val alpha: Boolean,
        val vulkan: Boolean,
        val normalFastPath: Boolean,
        private val requestedDepth: Boolean = false,
        private val requestedTopBottom: Boolean = false
    ) {
        val stereo get() = requestedStereo
        val depth get() = false
        val topBottom get() = requestedTopBottom
        val id get() = scope.decoderId
        val lock = Any()
        val disposed = AtomicBoolean(false)
        val display = PairDisplayGate(scope, depth = 2)
        val end = MpvEndGate(scope)
        val normal = FramePairGate(scope)
        val output = PlaybackDisplayLeases()
        var captureStartedNs = 0L
        var captureReadyCount = 0L
        var captureReadyUs = 0L
        var captureReadyMaxUs = 0L
        var deferredCopies = 0L
        var sourceEpoch = 0L
        var latestPair = ""
        var firstPair = false
        var captured = 0L
        var ownerDraws = 0L
        var uniquePostDrawFrames = 0L
        var lastUniquePostDrawNs = 0L
        var maxUniquePostDrawGapNs = 0L
        var lastPostDrawFrame = -1L
        var lastPostDrawEpoch = -1L
        var drawnToken = 0L
        val dims = profile.split('x').map { it.toInt() }

    }

    fun supported() = !stopped && MpvSourceNative.supported()

    /** User setting: decoded color width cap for sources opened from now on (0 = source size). */
    @Volatile
    var outputWidthCap = 0
    private fun frameCap(session: Session) =
        if (BuildConfig.DEBUG && debugFrameCapOverride >= 0) debugFrameCapOverride else 0

    private fun active(session: Session) =
        !stopped && !session.disposed.get() && gate.accepts(session.id)

    private fun event(name: String, session: Session, json: JSONObject) {
        json.put("session_id", session.id).put("logical_session_id", session.scope.logicalSessionId)
            .put("generation", session.scope.generation).put("backend", "Android_libmpv")
        emit(name, session.id, json.toString())
    }

    @Synchronized
    fun open(
        uri: String, startMs: Int, stereo: Boolean, profile: String,
        alpha: Boolean, vulkan: Boolean, hardware: Boolean = true, audio: Boolean = true,
        depth: Boolean = false, topBottom: Boolean = false, exactSeek: Boolean = false
    ): Int {
        if (alpha || depth) return -1
        if (!supported() || sessions.size >= 2 || startMs < 0 || profile !in BUFFER_SHAPES || (depth && (alpha || stereo)) ||
            Uri.parse(uri).scheme !in setOf(
                "content",
                "file",
                "smb",
                "cloud",
                "medialib",
                "http",
                "https"
            )
        ) return -1
        val id = gate.begin(); if (id <= 0) return -1
        val host = PlaybackHost(uri, startMs, hardware, audio, exactSeek, releaseNetwork)
        val session = Session(
            gate.current(id) ?: return -1,
            host,
            stereo,
            profile,
            alpha,
            vulkan,
            debugNormalFastPath,
            depth,
            stereo && topBottom
        )
        sessions[id] = session; hosts.add(host)
        sessions.values.filter { it.id != id }.forEach { dispose(it, true) }
        worker.post {
            try {
                host.markStartup("worker_started_ms")
                if (host.closing || stopped) return@post
                val app = context() ?: error("Activity unavailable")
                val path = host.resources.resolve(app, uri, resolveNetwork)
                host.markStartup("source_resolved_ms")
                // Extra audio is optional: a failed lookup plays the video without it.
                val extra = if (audio) sidecarAudio(uri) else emptyList()
                host.markStartup("audio_sidecars_resolved_ms")
                host.resources.adoptAudio(extra)
                val captions = sidecarSubtitles(uri)
                host.markStartup("subtitle_sidecars_resolved_ms")
                host.resources.adoptSubtitles(captions)
                if (host.closing || stopped) {
                    host.closeDescriptors(); return@post
                }
                render(Runnable {
                    if (host.closing || stopped) return@Runnable
                    try {
                        host.owner = EGL14.eglGetCurrentContext()
                        host.markStartup("native_create_started_ms")
                        host.handle = MpvSourceNative.create(
                            app,
                            path,
                            startMs,
                            hardware,
                            audio,
                            outputWidthCap,
                            extra.flatMap { listOf(it.location, it.title) }.toTypedArray(),
                            captions.flatMap { listOf(it.location, it.title) }.toTypedArray(),
                            host.exactStart
                        )
                        check(host.handle > 0)
                        host.markStartup("native_created_ms")
                        synchronized(host) {
                            check(MpvSourceNative.setSpeed(host.handle, host.speed))
                            host.subtitleCommand =
                                MpvSourceNative.setSync(host.handle, host.subtitleMs, host.audioMs)
                            check(host.subtitleCommand > 0)
                        }
                        MpvSourceNative.setFrameCap(host.handle, frameCap(session))
                        // Native creation stays paused until focus policy has
                        // run off the Godot GL thread.
                        refreshPlayback()
                    } catch (failure: Throwable) {
                        fail(session, "MPV_SOURCE_START_FAILED", failure)
                    }
                })
            } catch (failure: Throwable) {
                fail(session, "MPV_LOCAL_SOURCE_FAILED", failure)
            }
        }
        return id
    }
    /** Model result -> GL upload into the pair's mask. True hands the color lease to the uploader. */
    /** Returns a new processing generation without reopening the MPV media/audio core. */
    @Synchronized
    fun revise(
        id: Int, stereo: Boolean, alpha: Boolean, profile: String, positionMs: Int = -1,
        depth: Boolean = false, topBottom: Boolean = false, exactSeek: Boolean = false
    ): Int {
        if (alpha || depth) return -1
        val old = sessions[id] ?: return -1
        if (!active(old) || sessions.size >= 2 || profile !in BUFFER_SHAPES || (depth && (alpha || stereo))) return -1
        val host = old.host
        if (positionMs >= 0 && (host.handle <= 0 || !MpvSourceNative.seek(
                host.handle,
                positionMs.toLong(),
                exactSeek
            ))
        ) return -1
        val next = gate.replace(id); if (next <= 0) return -1
        val session = Session(
            gate.current(next) ?: return -1,
            host,
            stereo,
            profile,
            alpha,
            old.vulkan,
            old.normalFastPath,
            depth,
            stereo && topBottom
        )
        sessions[next] = session; dispose(old, false)
        if (host.handle > 0) MpvSourceNative.setFrameCap(host.handle, frameCap(session))
        if (host.handle > 0 && positionMs < 0) MpvSourceNative.requestFrame(host.handle)
        return next
    }

    fun setPlaying(id: Int, playing: Boolean) {
        val session = sessions[id] ?: return
        if (!active(session)) return
        session.host.playing = playing
        if (!playing && session.host.handle > 0) MpvSourceNative.setPlaying(
            session.host.handle,
            false
        )
        refreshPlayback(explicit = playing)
    }

    fun setSpeed(id: Int, speed: Double): Boolean {
        if (!speed.isFinite() || speed !in 0.25..3.0) return false
        val session = sessions[id] ?: return false
        synchronized(session.host) {
            if (!active(session) || session.host.closing) return false
            if (session.host.handle > 0 && !MpvSourceNative.setSpeed(
                    session.host.handle,
                    speed
                )
            ) return false
            session.host.speed = speed
            return true
        }
    }

    fun setAudio(id: Int, trackId: Int, volume: Double, muted: Boolean): Boolean {
        val session = sessions[id] ?: return false
        if (!active(session) || session.host.handle <= 0) return false
        if (trackId != 0 && !session.host.audioEnabled) MpvSourceNative.setPlaying(
            session.host.handle,
            false
        )
        val accepted = MpvSourceNative.setAudio(session.host.handle, trackId, volume, muted)
        if (accepted) session.host.audioEnabled = trackId != 0
        refreshPlayback(explicit = accepted && trackId != 0)
        return accepted
    }

    fun setSync(id: Int, subtitleMs: Int, audioMs: Int): Boolean {
        if (subtitleMs !in -10000..10000 || audioMs !in -10000..10000) return false
        val session = sessions[id] ?: return false
        synchronized(session.host) {
            if (!active(session) || session.host.closing) return false
            if (session.host.handle > 0) {
                val serial = MpvSourceNative.setSync(session.host.handle, subtitleMs, audioMs)
                if (serial <= 0) return false
                session.host.subtitleCommand = maxOf(session.host.subtitleCommand, serial)
            }
            session.host.subtitleMs = subtitleMs; session.host.audioMs = audioMs
            return true
        }
    }

    fun addSubtitle(id: Int, text: String): Boolean {
        val session = sessions[id] ?: return false
        val uri = Uri.parse(text)
        if (!active(session) || session.host.handle <= 0 || text.length > 8192 || uri.scheme !in setOf(
                "content",
                "file"
            ) ||
            !session.host.importingSubtitle.compareAndSet(false, true)
        ) return false
        val queued = PlaybackWorkers.subtitles.post {
            var temporary: File? = null
            try {
                val app = context() ?: error("Activity unavailable")
                var name = uri.lastPathSegment.orEmpty()
                if (uri.scheme == "content") app.contentResolver.query(
                    uri,
                    arrayOf(OpenableColumns.DISPLAY_NAME),
                    null,
                    null,
                    null
                )?.use {
                    if (it.moveToFirst()) name = it.getString(0).orEmpty()
                }
                val extension = SubtitleImport.extension(name)
                val staged = File.createTempFile("subtitle-", ".$extension", app.cacheDir)
                temporary = staged
                val input = if (uri.scheme == "file") File(
                    uri.path ?: error("Subtitle path missing")
                ).inputStream()
                else app.contentResolver.openInputStream(uri) ?: error("Subtitle permission lost")
                input.use { source ->
                    staged.outputStream().use { SubtitleImport.copy(source, it) }
                }
                synchronized(session.host) {
                    val current =
                        sessions.values.firstOrNull { it.host === session.host && active(it) }
                    check(current != null && !session.host.closing && session.host.handle > 0) { "Subtitle session changed" }
                    check(session.host.resources.importedSubtitles.size < 16) { "Too many imported subtitles; reopen the video" }
                    val serial = MpvSourceNative.addSubtitle(
                        session.host.handle,
                        staged.absolutePath,
                        name.take(256)
                    )
                    check(serial > 0) { "Subtitle import busy" }
                    session.host.resources.importedSubtitles.add(staged)
                    temporary = null // MPV may read it until the host fully closes.
                    session.host.subtitleCommand = maxOf(session.host.subtitleCommand, serial)
                    event(
                        "mpv_subtitle_import",
                        current,
                        JSONObject().put("state", "queued").put("uri", text).put("command", serial)
                    )
                }
            } catch (failure: Exception) {
                sessions.values.firstOrNull { it.host === session.host && active(it) }
                    ?.let { current ->
                        event(
                            "mpv_subtitle_import",
                            current,
                            JSONObject().put("state", "error")
                                .put("error", failure.message ?: "Subtitle import failed")
                        )
                    }
            } finally {
                temporary?.delete(); session.host.importingSubtitle.set(false)
            }
        }
        if (!queued) session.host.importingSubtitle.set(false)
        return queued
    }

    fun setSubtitle(id: Int, trackId: Int): Boolean {
        val session = sessions[id] ?: return false
        if (!active(session) || session.host.handle <= 0 || trackId < -1) return false
        val serial = MpvSourceNative.setSubtitle(session.host.handle, trackId)
        if (serial <= 0) return false
        synchronized(session.host) {
            session.host.subtitleCommand = maxOf(session.host.subtitleCommand, serial)
        }
        return true
    }

    fun subtitles(id: Int, afterSequence: Long): String {
        val session = sessions[id] ?: return ""
        if (!active(session) || session.host.handle <= 0 || afterSequence < 0) return ""
        val text = MpvSourceNative.subtitleStatus(session.host.handle, afterSequence)
        if (text.isEmpty() || !active(session)) return ""
        return JSONObject(text).put("session_id", session.id)
            .put("generation", session.scope.generation)
            .put("mpv_source_handle", session.host.handle)
            .put("required_command_id", session.host.subtitleCommand).toString()
    }


    private fun refreshPlayback(explicit: Boolean = false) {
        worker.post {
            val needsAudio = !stopped && foreground && hosts.any {
                !it.closing && it.handle > 0 && it.playing && it.audioEnabled && it.audioAvailable
            }
            if (needsAudio && audioFocus == null) context()?.let { app ->
                audioFocus = MpvAudioFocus(app) { change ->
                    if (change != MpvAudioFocusGate.Change.GAIN) audioFocusInterruptions.incrementAndGet()
                    // Stop as soon as loss arrives; waiting for RVM work to
                    // finish must not keep audio playing over another app.
                    if (change != MpvAudioFocusGate.Change.GAIN) hosts.filter { !stopped && !it.closing && it.audioEnabled && it.audioAvailable }
                        .forEach {
                            if (change == MpvAudioFocusGate.Change.LOSS) it.playing = false
                            if (it.handle > 0) MpvSourceNative.setPlaying(it.handle, false)
                        }
                    if (change == MpvAudioFocusGate.Change.LOSS) sessions.values.filter { active(it) && it.host.audioEnabled && it.host.audioAvailable }
                        .forEach {
                            event(
                                "mpv_state",
                                it,
                                JSONObject().put("state", "paused")
                                    .put("audio_focus_change", "loss")
                            )
                        }
                    refreshPlayback()
                }
            }
            val granted = if (needsAudio) audioFocus?.acquire(explicit) == true else {
                audioFocus?.release(); true
            }
            audioFocusState = if (needsAudio) audioFocus?.state() ?: "unavailable" else "none"
            hosts.forEach { host ->
                if (!stopped && !host.closing && host.handle > 0) {
                    MpvSourceNative.setPlaying(
                        host.handle, foreground && host.playing &&
                                (!(host.audioEnabled && host.audioAvailable) || granted)
                    )
                }
            }
        }
    }

    fun draw() {
        for (session in sessions.values) synchronized(session.lock) {
            try {
                if (session.disposed.get()) {
                    cleanup(session); return@synchronized
                }
                if (!active(session) || session.host.handle == 0L) return@synchronized
                check(session.host.owner == EGL14.eglGetCurrentContext()) { "MPV owner GL context changed" }
                if (session.output.renderer > 0) {
                    pollRetirements(session); finishUploads(session)
                    if (session.display.drawn(session.drawnToken)) {
                        session.ownerDraws++
                        session.output.pairs[session.drawnToken]?.let { pair ->
                            val frame = pair.getLong("frame_id")
                            val epoch = pair.getLong("source_epoch")
                            if (frame != session.lastPostDrawFrame || epoch != session.lastPostDrawEpoch) {
                                val now = System.nanoTime()
                                if (session.lastUniquePostDrawNs > 0L)
                                    session.maxUniquePostDrawGapNs = maxOf(
                                        session.maxUniquePostDrawGapNs,
                                        now - session.lastUniquePostDrawNs
                                    )
                                session.lastUniquePostDrawNs = now
                                session.uniquePostDrawFrames++
                                session.lastPostDrawFrame = frame
                                session.lastPostDrawEpoch = epoch
                            }
                            session.end.postDraw(identity(pair), pair.getLong("source_epoch"))
                        }
                    }
                }
                finishCopy(session)
                if (session.normalFastPath) finishUploads(session)
                if (session.output.copying != null) return@synchronized
                // Open/revise starts MPV paused until Godot displays the first complete pair.
                // Taking that frame before RVM is ready drops it in drain(); paused MPV then
                // has no new frame to offer and the Alpha transition never completes.
                run {
                    val source =
                        session.output.pendingSource ?: MpvSourceNative.acquire(session.host.handle)
                            .takeIf { it.isNotEmpty() }?.let { JSONObject(it) }
                    session.output.pendingSource = null
                    if (source != null && !capture(session, source)) {
                        session.output.pendingSource = source
                        session.deferredCopies++
                    }
                    // Cached opaque borrowing can be ready immediately: no copy or upload was
                    // submitted. Offer that pair in this draw instead of waiting another tick.
                    if (session.normalFastPath) {
                        finishCopy(session); finishUploads(session)
                    }
                }
                if (System.nanoTime() >= session.host.nextStatusNs) {
                    session.host.nextStatusNs = System.nanoTime() + 250_000_000L
                    val status = JSONObject(MpvSourceNative.status(session.host.handle))
                    if (BuildConfig.DEBUG && session.output.renderer > 0)
                        status.put(
                            "bridge",
                            JSONObject(RenderBridgeNative.stats(session.output.renderer))
                        )
                    status.put("normal_fast_path", session.normalFastPath)
                        .put("video_fps_cap", frameCap(session))
                    val details = status.optJSONObject("details")
                    if (!details?.optString("codec").isNullOrEmpty()) {
                        val available = (details?.optJSONArray("audio_tracks")?.length()
                            ?: 0) > 0 && session.host.audio
                        if (available != session.host.audioAvailable) {
                            session.host.audioAvailable = available; refreshPlayback()
                        }
                    }
                    val terminal =
                        if (status.optBoolean("eof_source_resolved")) status.optJSONObject("eof_source_ticket") else null
                    session.end.observe(terminal?.let {
                        MpvEndGate.Source(
                            it.getLong("source_epoch"),
                            it.getLong("frame_id"),
                            it.getLong("pts_us")
                        )
                    })
                    event(
                        "mpv_state",
                        session,
                        status.put("alpha_requested", session.alpha)
                            .put("depth_requested", session.depth)
                            .put("startup_bridge", JSONObject(session.host.startup as Map<*, *>))
                            .put("captured_frames", session.captured)
                            .put("capture_ready_count", session.captureReadyCount)
                            .put("capture_to_ready_us", session.captureReadyUs)
                            .put("capture_to_ready_max_us", session.captureReadyMaxUs)
                            .put("display_claims", session.display.heldClaims())
                            .put("post_draw_frames", session.ownerDraws)
                            .put("unique_post_draw_frames", session.uniquePostDrawFrames)
                            .put("display_rejected_pairs", session.display.rejectedCount)
                            .put("display_clock_corrections", session.display.clockCorrections)
                            .put("post_draw_gap_max_us", session.maxUniquePostDrawGapNs / 1000L)

                            .put("producer_copy_deferred", session.deferredCopies)
                            .put("producer_copy_pending", session.output.pendingSource != null)
                            .put("eof_pair_post_draw", session.end.complete())
                            .put("eof_presented_slot", session.end.completedSlot())
                            .put("audio_focus", audioFocusState).put("foreground", foreground)
                            .put("requested_play", session.host.playing)
                            .put("lifecycle_pauses", lifecyclePauses.get())
                            .put("audio_focus_interruptions", audioFocusInterruptions.get())
                    )
                    if (status.optString("state") == "failed" || status.optBoolean("render_failed"))
                        error(status.optString("error") + " " + status.optString("render_error"))
                }
            } catch (failure: Throwable) {
                fail(session, "MPV_FRAME_PIPELINE_FAILED", failure)
            }
        }
        for (host in hosts) if (host.closing && sessions.values.none { it.host === host }) {
            try {
                if (host.handle == 0L || MpvSourceNative.close(
                        host.handle,
                        host.owner != EGL14.eglGetCurrentContext()
                    )
                ) {
                    host.handle = 0; host.closeDescriptors(); hosts.remove(host)
                }
            } catch (_: Throwable) { /* Preserve ownership and retry; never close a descriptor still used by MPV. */
            }
        }
    }

    private fun capture(session: Session, source: JSONObject): Boolean {
        session.captureStartedNs = System.nanoTime()
        val producer = source.getLong("producer_token")
        var releaseProducer = true
        try {
            check(
                source.getBoolean("source_ticket_valid") && source.getBoolean("producer_fence_ready") && source.getBoolean(
                    "owner_context_shared"
                )
            )
            val width = source.getInt("width");
            val height = source.getInt("height")
            check(!session.stereo || (if (session.topBottom) height else width) % 2 == 0)
            val epoch = source.getLong("source_epoch")
            if (session.sourceEpoch == 0L) session.sourceEpoch = epoch
            check(session.sourceEpoch == epoch) { "Source epoch changed without processing generation reset" }
            if (session.output.renderer == 0L) {
                session.output.owner = EGL14.eglGetCurrentContext()
                session.output.renderer = RenderBridgeNative.create(
                    width,
                    height,
                    session.dims[0],
                    session.dims[1],
                    session.stereo,
                    session.topBottom
                )
                // Ordinary playback also keeps the immutable MPV texture until Godot's last draw.
                // Avoid a second full-resolution RGBA read/write (256 MiB per 8192x4096 frame).
                // retire()/cleanup() release the producer through a consumer-context GPU fence;
                // display pins, seeks and mode changes retain the same ownership rules as Alpha.
                if (session.normalFastPath && !debugBorrowDisabled)
                    session.output.borrow =
                        RenderBridgeNative.enableBorrowedColor(session.output.renderer)
            }
            val token = if (session.normalFastPath)
                RenderBridgeNative.captureOpaqueTexture(
                    session.output.renderer,
                    source.getInt("color_texture_id")
                )
            else RenderBridgeNative.captureTexture(
                session.output.renderer,
                source.getInt("color_texture_id")
            )
            if (token == 0L) {
                // A full consumer ring must not consume the only remaining EOF
                // frame. Keep the immutable producer lease and retry next draw.
                releaseProducer = false
                return false
            }
            if (session.output.borrow) {
                session.output.copyingProducer = producer; releaseProducer = false
            }
            val ticket = DecodedFrameGate.Ticket(
                session.scope,
                source.getLong("frame_id"),
                source.getLong("pts_us"),
                1,
                1
            )
            PlaybackFrameContract.color(
                source,
                session.scope,
                token,
                session.host.handle,
                session.stereo,
                session.topBottom
            )
            session.output.copying = ticket to token; session.output.copyingPair = source
            return true
        } finally {
            // This consumer fence follows the full-resolution GPU copy and small
            // input staging. There is never a CPU readback of the source image.
            if (releaseProducer)
                check(
                    MpvSourceNative.release(
                        session.host.handle,
                        producer
                    )
                ) { "Producer lease release failed" }
        }
    }

    private fun finishCopy(session: Session) {
        val copying = session.output.copying ?: return
        if (!RenderBridgeNative.ready(session.output.renderer, copying.second)) return
        val readyUs = (System.nanoTime() - session.captureStartedNs) / 1000
        session.captureReadyCount++
        session.captureReadyUs += readyUs
        session.captureReadyMaxUs = maxOf(session.captureReadyMaxUs, readyUs)
        val texture = RenderBridgeNative.texture(session.output.renderer, copying.second)
        val pair = session.output.copyingPair ?: error("Immutable copy descriptor missing")
        // Decoder images get a new texture each frame and always use zero-copy: no CPU planes.
        pair.put("color_texture_id", texture).put("consumer_copy_fence_ready", true)
        val lease = PlaybackDisplayLeases.Lease(copying.first, pair, session.output.copyingProducer)
        session.output.copyingProducer = 0L
        session.output.leases[copying.second] = lease
        session.output.copying = null; session.output.copyingPair = null; session.captured++
        check(
            RenderBridgeNative.alphaReady(
                session.output.renderer,
                copying.second
            )
        ) { "Opaque mask must share the completed color fence" }
        session.output.alphaUploads[copying.second] = PlaybackDisplayLeases.ReadyMask(pair)
    }

    private fun finishUploads(session: Session) {
        val iterator = session.output.alphaUploads.iterator()
        while (iterator.hasNext()) {
            val (token, upload) = iterator.next()
            if (!RenderBridgeNative.alphaReady(session.output.renderer, token)) continue
            iterator.remove()
            val pair = PlaybackFrameContract.complete(
                upload.pair,
                upload.pair.getInt("color_texture_id"),
                RenderBridgeNative.alphaTexture(session.output.renderer, token),
                session.dims[0],
                session.dims[1]
            )
            val obsolete = session.display.offer(identity(pair))
            if (obsolete == token) {
                retire(session, token); continue
            }
            obsolete?.let { retire(session, it) }
            session.output.pairs[token] = pair; session.latestPair = pair.toString()
            // Godot claims the oldest ready pair; a newer one is offered once that is claimed. When a full
            // queue drops the oldest (the one Godot was told about), tell Godot the new oldest: otherwise its
            // claim of the dropped pair fails and no notice ever comes again (frozen picture at high rates).
            val head = session.display.readyToken()
            if (head != null && (head == token || obsolete != null))
                session.output.pairs[head]?.let {
                    emit(
                        "mpv_pair_available",
                        session.id,
                        it.toString()
                    )
                }
        }
    }

    private fun identity(pair: JSONObject) = PlaybackFrameContract.identity(pair)
    fun claim(id: Int, token: Long): String {
        val session = sessions[id] ?: return ""
        val next: String?
        val claimed: String
        synchronized(session.lock) {
            if (!active(session) || session.display.claim(token) == null) return ""
            claimed = session.output.pairs[token]?.toString() ?: ""
            next = session.display.readyToken()?.let { session.output.pairs[it]?.toString() }
        }
        // The next ready pair (a burst) is drawn on Godot's following frame.
        next?.let { emit("mpv_pair_available", session.id, it) }
        return claimed
    }

    /** Capture on a real owner draw callback, while the original display claim is pinned.
     * Its returned copy outlives the old processing session, without a decoder lease. */
    fun freeze(id: Int, token: Long, request: Int): Boolean {
        val session = sessions[id] ?: return false
        if (request <= 0 || !freezePending.compareAndSet(false, true)) return false
        synchronized(session.lock) {
            if (!active(session) || !session.display.pin(token)) {
                freezePending.set(false); return false
            }
        }
        try {
            render(Runnable {
                synchronized(session.lock) {
                    val report = JSONObject().put("request_id", request).put("slot_token", token)
                    try {
                        check(active(session)) { "Freeze source no longer active" }
                        val pair = JSONObject(session.output.pairs.getValue(token).toString())
                        val copy = RenderBridgeNative.freezePair(session.output.renderer, token)
                        frozenFrames[copy[0]] = AtomicInteger(1)
                        pair.put("frozen_frame_id", copy[0]).put("freeze_copy_us", copy[5])
                            .put("color_target", "texture").put("color_texture_id", copy[1])
                            .put("alpha_texture_id", copy[2]).put("color_egl_image", "0")

                        report.put("pair", pair).put("state", "ready")
                    } catch (failure: Throwable) {
                        report.put("state", "failed").put("error", failure.message)
                        if (BuildConfig.DEBUG) android.util.Log.w(
                            "QuestMpvFreeze",
                            "Frame freeze failed",
                            failure
                        )
                    } finally {
                        session.display.unpin(token); freezePending.set(false)
                        release(session, token)
                    }
                    emit("mpv_frozen_pair", session.id, report.toString())
                }
            })
            return true
        } catch (_: Throwable) {
            synchronized(session.lock) { session.display.unpin(token) }
            freezePending.set(false)
            return false
        }
    }

    fun releaseFrozen(id: Long) {
        if (id <= 0) return
        render(Runnable {
            val refs = frozenFrames[id] ?: return@Runnable
            if (refs.decrementAndGet() == 0 && frozenFrames.remove(
                    id,
                    refs
                )
            ) RenderBridgeNative.releaseFrozen(id)
        })
    }

    fun retainFrozen(id: Long): Boolean {
        val refs = frozenFrames[id] ?: return false
        while (true) {
            val count = refs.get()
            if (count <= 0) return false
            if (refs.compareAndSet(count, count + 1)) return true
        }
    }

    fun acknowledge(id: Int, token: Long): Boolean {
        val session = sessions[id] ?: return false
        synchronized(session.lock) {
            val pair = session.output.pairs[token] ?: return false
            if (!active(session) || !session.display.acknowledge(token)) return false
            session.drawnToken = token; pair.put("pair_presented", true); session.firstPair = true
            session.host.markStartup("first_pair_bound_ms")
            return true
        }
    }

    fun detach(id: Int, token: Long): Boolean {
        val session = sessions[id] ?: return false
        synchronized(session.lock) { if (!session.display.detach(token)) return false }
        render(Runnable {
            synchronized(session.lock) {
                if (session.output.renderer > 0 && session.output.owner == EGL14.eglGetCurrentContext() && !session.display.owns(
                        token
                    )
                ) retire(session, token)
            }
        })
        return true
    }

    private fun release(session: Session, token: Long) {
        render(Runnable {
            synchronized(session.lock) {
                if (session.output.renderer > 0 && session.output.owner == EGL14.eglGetCurrentContext() && !session.display.owns(
                        token
                    )
                ) retire(session, token)
            }
        })
    }

    private fun retire(session: Session, token: Long) {
        check(!session.display.owns(token)) { "Cannot retire a Godot display claim" }
        val lease = session.output.leases.remove(token) ?: return
        session.output.pairs.remove(token)
        RenderBridgeNative.retire(
            session.output.renderer,
            token
        ); session.output.retiring.add(token)
        // After the bridge fence: the MPV slot may be reused once every draw of this pair completes.
        if (lease.producer > 0) check(
            MpvSourceNative.release(
                session.host.handle,
                lease.producer
            )
        ) { "Borrowed producer release failed" }
    }

    fun requestPixelMask(request: Int, id: Int, token: Long): Boolean {
        if (!BuildConfig.DEBUG || request <= 0) return false
        val session = sessions[id] ?: return false
        val pair = synchronized(session.lock) {
            if (!active(session) || !session.output.pairs.containsKey(token) || !session.display.pin(
                    token
                )
            ) return false
            JSONObject(session.output.pairs.getValue(token).toString())
        }
        try {
            render(Runnable {
                synchronized(session.lock) {
                    val report = JSONObject().put("request_id", request).put("pair", pair)
                    try {
                        check(session.output.renderer > 0 && session.output.owner == EGL14.eglGetCurrentContext())
                        val pixels = pair.getInt("alpha_width") * pair.getInt("alpha_height")
                        val buffer = ByteBuffer.allocateDirect(pixels)
                        check(RenderBridgeNative.readAlpha(session.output.renderer, token, buffer))
                        val bytes = ByteArray(pixels); buffer.position(0); buffer.get(bytes)
                        val app = context() ?: error("Activity unavailable")
                        val directory = java.io.File(app.filesDir, "diagnostics").apply { mkdirs() }
                        val name = "mpv_pixel_mask_$request.r8"
                        val temporary = java.io.File.createTempFile("mask-", ".tmp", directory)
                        try {
                            temporary.writeBytes(bytes); check(
                                temporary.renameTo(
                                    java.io.File(
                                        directory,
                                        name
                                    )
                                )
                            )
                        } finally {
                            temporary.delete()
                        }
                        report.put("state", "ready").put("mask_file", name)
                            .put("mask_bytes", pixels)
                            .put("mask_origin", "same_pinned_pair_native_R8_readback")
                    } catch (failure: Throwable) {
                        report.put("state", "failed").put("error", failure.message)
                        unpinPixelPair(id, token)
                    }
                    emit("mpv_pixel_mask", request, report.toString())
                }
            })
            return true
        } catch (_: Throwable) {
            synchronized(session.lock) { session.display.unpin(token) }
            return false
        }
    }

    fun unpinPixelPair(id: Int, token: Long): Boolean {
        if (!BuildConfig.DEBUG) return false
        return unpinPair(id, token)
    }

    fun pinPair(id: Int, token: Long): Boolean {
        val session = sessions[id] ?: return false
        synchronized(session.lock) { return active(session) && session.display.pin(token) }
    }

    fun unpinPair(id: Int, token: Long): Boolean {
        val session = sessions[id] ?: return false
        synchronized(session.lock) { if (!session.display.unpin(token)) return false }
        release(session, token)
        return true
    }

    private fun pollRetirements(session: Session) {
        val iterator = session.output.retiring.iterator()
        while (iterator.hasNext()) if (RenderBridgeNative.retired(
                session.output.renderer,
                iterator.next()
            )
        ) iterator.remove()
    }

    private fun cleanup(session: Session) {
        session.output.pendingSource?.let { source ->
            if (session.host.owner == EGL14.eglGetCurrentContext()) {
                check(
                    MpvSourceNative.release(
                        session.host.handle,
                        source.getLong("producer_token")
                    )
                )
            } else {
                // The lost owner context cannot insert a consumer release fence.
                session.host.closing = true
                MpvSourceNative.close(session.host.handle, true)
            }
            session.output.pendingSource = null
        }
        if (session.output.renderer > 0) {
            if (session.output.owner != EGL14.eglGetCurrentContext()) {
                RenderBridgeNative.abandon(session.output.renderer); session.output.renderer =
                    0; session.output.retiring.clear()
            } else {
                session.output.copying?.let {
                    RenderBridgeNative.retire(
                        session.output.renderer,
                        it.second
                    ); session.output.retiring.add(it.second)
                }
                if (session.output.copyingProducer > 0) MpvSourceNative.release(
                    session.host.handle,
                    session.output.copyingProducer
                )
                session.output.copyingProducer = 0L
                session.output.copying = null; session.output.copyingPair =
                    null; session.output.alphaUploads.clear()
                session.output.leases.keys.toList().filter { !session.display.owns(it) }
                    .forEach { retire(session, it) }
                pollRetirements(session)
            }
        }
        if (session.display.heldClaims() > 0 || session.output.retiring.isNotEmpty()) return
        if (session.output.renderer > 0) RenderBridgeNative.close(session.output.renderer)
        session.output.renderer = 0; session.output.leases.clear(); session.output.pairs.clear()
        sessions.remove(session.id)
        event(
            "mpv_released",
            session,
            JSONObject().put("renderer_closed", true).put("held_slots", 0)
        )
    }

    private fun dispose(session: Session, closeHost: Boolean) {
        if (!session.disposed.compareAndSet(false, true)) return
        session.normal.close()
        synchronized(session.lock) { session.display.close() }
        if (closeHost) {
            session.host.closing = true
            if (session.host.handle > 0) MpvSourceNative.setPlaying(session.host.handle, false)
            refreshPlayback()
        }
        event("mpv_detach", session, JSONObject().put("reason", "generation_invalidated"))
    }

    private fun fail(session: Session, code: String, failure: Throwable) {
        if (session.disposed.get()) return
        event("mpv_error", session, JSONObject().put("code", code).put("message", failure.message))
        gate.invalidate(session.id); dispose(session, true)
    }

    fun close(id: Int) {
        sessions[id]?.let { gate.invalidate(id); dispose(it, true) }
    }

    fun pause() {
        lifecyclePauses.incrementAndGet()
        foreground = false; hosts.forEach {
            if (it.handle > 0) MpvSourceNative.setPlaying(
                it.handle,
                false
            )
        }
        refreshPlayback()
    }

    fun resume() {
        foreground = true; refreshPlayback()
    }

    fun contextCreated() {
        frozenFrames.keys.toList()
            .forEach { RenderBridgeNative.releaseFrozen(it); frozenFrames.remove(it) }
        // A real recreated context invalidates the complete pipeline. Initial
        // creation has no sessions; UI can reopen the same authorized URI.
        sessions.values.forEach {
            fail(
                it,
                "MPV_GL_CONTEXT_RECREATED",
                IllegalStateException("Owner context recreated")
            )
        }
    }

    companion object {
        private val BUFFER_SHAPES =
            setOf("320x320", "384x216", "512x288", "384x384", "512x512", "256x144", "256x256")
    }

    fun shutdown() {
        stopped = true; gate.shutdown(); sessions.values.forEach { dispose(it, true) }
        // Android may never deliver another draw during termination. Forget old
        // owner references and let each shared native context release its objects.
        hosts.forEach { host -> if (host.handle > 0) MpvSourceNative.close(host.handle, true) }
        Thread({
            for (host in hosts.toList()) {
                while (host.handle > 0) {
                    if (MpvSourceNative.close(host.handle, true)) {
                        host.handle = 0; break
                    }
                    Thread.sleep(20)
                }
                host.closeDescriptors()
            }
        }, "QuestMpvDispose").start()
        // Session resources close above; the shared playback worker survives
        // Activity recreation so playback callbacks retain one worker owner.
    }
}
