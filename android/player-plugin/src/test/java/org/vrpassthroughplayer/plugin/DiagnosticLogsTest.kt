package org.vrpassthroughplayer.plugin

import java.nio.file.Files
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class DiagnosticLogsTest {
    @Test
    fun nestedCredentialsAreRedactedAndEventsRotateWithBoundedExports() {
        val folder = Files.createTempDirectory("diagnostic-log").toFile()
        try {
            val raw =
                JSONObject()
                    .put("event", "setting")
                    .put(
                        "details",
                        JSONObject()
                            .put("username", "Alice Example")
                            .put("nested", JSONObject().put("api_key", "secret"))
                            .put("url", "https://nas/video?signature=signed"),
                    )
            val clean = (DiagnosticLogs.clean(raw) as JSONObject).toString()
            for (secret in listOf("Alice", "secret", "signed", "nas/video")) assertFalse(
                clean.contains(secret)
            )
            repeat(200) {
                DiagnosticLogs.record(
                    folder,
                    "event",
                    JSONObject().put("event", "event").put("details", "x".repeat(2048)).toString(),
                )
            }
            assertTrue(java.io.File(folder, "events.1.jsonl").exists())
            assertTrue(
                folder.listFiles()!!.all {
                    it.length() <= DiagnosticLogs.EVENT_BYTES &&
                        it.name in setOf("events.jsonl", "events.1.jsonl")
                }
            )
            val exported = DiagnosticLogs.compose(folder)
            assertTrue(exported.toByteArray().size <= 512 * 1024)
            assertTrue(exported.contains("explicit user request"))
            assertFalse(
                DiagnosticLogs.redact(
                        "Authorization: Bearer abc123\n{\"password\":\"hello world\",\"email\":\"person@example.com\"}"
                    )
                    .contains("abc123")
            )
            assertFalse(
                DiagnosticLogs.redact(
                        "{\"password\":\"hello world\",\"email\":\"person@example.com\"}"
                    )
                    .contains("hello")
            )
        } finally {
            folder.deleteRecursively()
        }
    }
}
