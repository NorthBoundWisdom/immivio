package org.vrpassthroughplayer.plugin

import android.content.Context
import java.io.File

/** Private bounded records survive restart; public saving always goes through the consent action. */
internal object CrashRecords {
    private var started = false
    @Synchronized fun start(context: Context) {
        if (started) return
        started = true
        val directory = File(context.filesDir, "diagnostics/crash").apply { mkdirs() }
        val previous = runCatching { CrashTrail.open(File(directory, "trail.bin"), android.os.Process.myPid()) }.getOrNull()
        runCatching { recover(directory, previous, exitSummary(context, previous)) }
        val delegate = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler(handler(directory, delegate))
        CrashTrail.mark("app.start")
    }
    fun exceptionText(error: Throwable): String = buildString {
        val seen = java.util.Collections.newSetFromMap(java.util.IdentityHashMap<Throwable, Boolean>())
        var current: Throwable? = error
        repeat(4) {
            val item = current ?: return@repeat
            if (!seen.add(item)) return@repeat
            append(item.javaClass.name.take(256)).append(": ").append(DiagnosticLogs.redact(item.message.orEmpty()).take(1024)).append('\n')
            item.stackTrace.take(64).forEach { frame -> append(DiagnosticLogs.redact(frame.toString()).take(256)).append('\n') }
            current = item.cause
        }
    }.take(64 * 1024)
    fun handler(directory: File, delegate: Thread.UncaughtExceptionHandler?): Thread.UncaughtExceptionHandler = Thread.UncaughtExceptionHandler { thread, error ->
        runCatching {
            CrashTrail.mark("java.crash", error.javaClass.simpleName)
            write(File(directory, "java-crash.txt"), exceptionText(error))
        }
        if (delegate != null) delegate.uncaughtException(thread, error) else android.os.Process.killProcess(android.os.Process.myPid())
    }
    private fun write(file: File, value: String) {
        file.parentFile?.mkdirs()
        val staging = File(file.parentFile, file.name + ".tmp")
        try {
            staging.writeText(DiagnosticLogs.redact(value).take(128 * 1024), Charsets.UTF_8)
            java.nio.file.Files.move(staging.toPath(), file.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING)
        } finally { staging.delete() }
    }
    fun recover(directory: File, previous: CrashTrail.Session?, summary: String = ""): Boolean {
        val java = File(directory, "java-crash.txt")
        if ((previous == null || previous.clean) && !java.isFile) return false
        val report = buildString {
            append("Previous session ended without a clean shutdown marker. This may be a crash or OS process reclamation.\n")
            append(DiagnosticLogs.redact(summary)).append('\n')
            if (previous != null) append("Foreground: ${previous.foreground}\n").append(previous.lines.takeLast(160).joinToString("\n"))
            append("\n== Java exception ==\n").append(DiagnosticLogs.tail(java, 64 * 1024))
            append("\nNative binary tombstones and logcat are not included.\n")
        }
        write(File(directory, "last-report.txt"), report); java.delete(); return true
    }
    private fun exitSummary(context: Context, previous: CrashTrail.Session?): String {
        if (android.os.Build.VERSION.SDK_INT < 30 || previous == null) return "System exit reason unavailable"
        return runCatching {
            val manager = context.getSystemService(android.app.ActivityManager::class.java)
            manager.getHistoricalProcessExitReasons(context.packageName, previous.pid, 4)
                .filter { it.timestamp >= previous.startedMs }.take(4).joinToString("\n") {
                    "System exit: reason=${it.reason} status=${it.status} timestamp=${it.timestamp} " + DiagnosticLogs.redact(it.description.orEmpty()).take(512)
                }
        }.getOrDefault("System exit reason unavailable")
    }
    fun foreground(value: Boolean) { CrashTrail.foreground(value) }
    fun cleanExit() { CrashTrail.mark("app.exit"); CrashTrail.cleanExit() }
}
