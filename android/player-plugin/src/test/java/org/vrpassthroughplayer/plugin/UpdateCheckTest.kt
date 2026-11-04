package org.vrpassthroughplayer.plugin

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.net.URI
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class UpdateCheckTest {
    private fun body(tag: String, url: String? = UpdateCheck.releaseUrl(tag)) = JSONObject().put("tag_name", tag)
        .put("html_url", url ?: "https://github.com/NorthBoundWisdom/immivio/releases/tag/$tag").toString().toByteArray()
    @Test fun latestReleaseUsesNumericSemverAndValidatesTheTagAndExactReleaseUrl() {
        var reply = body("v0.10.0")
        val calls = AtomicInteger()
        MediaServerClientTest.Fixture { request, headers, _ ->
            calls.incrementAndGet()
            assertTrue(request.startsWith("GET /latest "))
            assertEquals("Immivio/0.9.4", headers["user-agent"])
            assertTrue(headers["authorization"].isNullOrEmpty())
            assertTrue(headers["cookie"].isNullOrEmpty())
            assertFalse(headers.keys.any { it.contains("token", true) || it.contains("apikey", true) })
            MediaServerClientTest.Reply(body = reply)
        }.use { fixture ->
            UpdateCheck(URI(fixture.url + "/latest")).use { checker ->
                assertEquals(0, calls.get()) // Construction does not check for updates.
                assertEquals("available", checker.check("0.9.4").state)
                reply = body("v0.9.4"); assertEquals("latest", checker.check("0.9.4").state)
                reply = body("v0.9.3"); assertEquals("latest", checker.check("0.9.4").state)
                for (tag in listOf("0.10.0", "v0.10", "v0.10.0-beta", "v0.10.0/extra", "v1.2.3\n")) {
                    reply = body(tag); assertEquals(tag, "invalid_response", checker.check("0.9.4").state)
                }
                for (url in listOf("https://evil.example/releases/tag/v0.10.0", "https://github.com.evil.example/NorthBoundWisdom/immivio/releases/tag/v0.10.0",
                    "https://github.com/NorthBoundWisdom/immivio/releases/tag/v0.10.0?token=secret", "https://github.com/other/immivio/releases/tag/v0.10.0")) {
                    reply = body("v0.10.0", url); assertEquals("invalid_response", checker.check("0.9.4").state)
                }
                reply = JSONObject(String(body("v0.10.0"))).put("prerelease", true).toString().toByteArray()
                assertEquals("invalid_response", checker.check("0.9.4").state)
            }
        }
        assertTrue(UpdateCheck.newer("2.0.0", "1.99.99"))
        assertFalse(UpdateCheck.newer("0001.02.003", "1.2.3"))
        assertTrue(UpdateCheck.newer("999999999999999999999999.0.0", "999999999999999999999998.0.0"))
        assertThrows(IllegalArgumentException::class.java) { UpdateCheck(URI("http://external.invalid/latest")) }
    }
    // Minimized from the one unauthenticated GitHub /releases/latest response captured 2026-11-04.
    @Test fun capturedGitHubReleaseStructureMatchesTheProductionVersionContract() {
        val fixture = JSONObject(requireNotNull(javaClass.getResource("/github-latest-release.json")).readText())
        val local = fixture.getString("tag_name").removePrefix("v")
        assertEquals(UpdateCheck.releaseUrl(fixture.getString("tag_name")), fixture.getString("html_url"))
        var response = fixture.toString().toByteArray()
        MediaServerClientTest.Fixture { _, _, _ -> MediaServerClientTest.Reply(body = response) }.use { server ->
            UpdateCheck(URI(server.url)).use { checker ->
                assertEquals("latest", checker.check(local).state)
                val parts = local.split('.')
                val newer = "v${parts[0]}.${parts[1]}.${parts[2].toInt() + 1}"
                response = JSONObject(fixture.toString()).put("tag_name", newer)
                    .put("html_url", UpdateCheck.releaseUrl(newer)).toString().toByteArray()
                assertEquals("available", checker.check(local).state)
            }
        }
    }
    @Test fun boundedTimeoutsRateLimitsAndCrossHostRedirectNeverBecomeSuccess() {
        var status = 403
        var headers = ""
        var response = byteArrayOf()
        var delay = 0L
        val redirectCalls = AtomicInteger()
        MediaServerClientTest.Fixture { _, _, _ ->
            redirectCalls.incrementAndGet()
            MediaServerClientTest.Reply(body = body("v9.9.9"))
        }.use { foreign -> MediaServerClientTest.Fixture { _, _, _ ->
            if (delay > 0) Thread.sleep(delay)
            MediaServerClientTest.Reply(status, headers, response)
        }.use { fixture ->
            UpdateCheck(URI(fixture.url), connectTimeoutMs = 100, readTimeoutMs = 50).use { checker ->
                for (code in listOf(403, 429)) { status = code; assertEquals("rate_limited", checker.check("0.9.4").state) }
                status = 302; headers = "Location: ${foreign.url.replace("127.0.0.1", "localhost")}/latest\r\n"
                assertEquals("invalid_response", checker.check("0.9.4").state)
                assertEquals(0, redirectCalls.get())
                status = 200; headers = ""; response = ByteArray(UpdateCheck.MAX_BYTES + 1)
                assertEquals("invalid_response", checker.check("0.9.4").state)
                response = body("v9.9.9"); delay = 200
                assertEquals("network_error", checker.check("0.9.4").state)
            }
        } }
    }
    @Test fun responseWithoutContentLengthStillCannotExceedTheReadBound() {
        java.net.ServerSocket(0, 1, java.net.InetAddress.getByName("127.0.0.1")).use { server ->
            val served = CountDownLatch(1)
            val thread = Thread {
                try {
                    server.accept().use { peer ->
                        val reader = peer.getInputStream().bufferedReader()
                        while (!reader.readLine().isNullOrEmpty()) { }
                        runCatching {
                            peer.getOutputStream().apply {
                                write("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n".toByteArray())
                                write(ByteArray(UpdateCheck.MAX_BYTES + 1) { 'x'.code.toByte() }); flush()
                            }
                        }
                    }
                } finally { served.countDown() }
            }.apply { isDaemon = true; start() }
            UpdateCheck(URI("http://127.0.0.1:${server.localPort}/latest")).use { checker ->
                assertEquals("invalid_response", checker.check("0.9.4").state)
            }
            assertTrue(served.await(3, TimeUnit.SECONDS)); thread.join(3000)
        }
    }
    @Test fun simultaneousRequestsAreIgnoredAndClosedOwnersNeverEmitLateResults() {
        val entered = CountDownLatch(1); val release = CountDownLatch(1); val reported = CountDownLatch(1)
        val calls = AtomicInteger(); val emitted = AtomicInteger()
        val worker = UpdateCheckRequests(perform = { version ->
            calls.incrementAndGet(); entered.countDown(); release.await(3, TimeUnit.SECONDS)
            UpdateCheck.Result("latest", version)
        }, emit = { _, _ -> emitted.incrementAndGet(); reported.countDown() })
        try {
            assertEquals(0, calls.get())
            assertTrue(worker.request("0.9.4") > 0)
            assertTrue(entered.await(3, TimeUnit.SECONDS))
            assertEquals(-1, worker.request("0.9.4")); assertEquals(1, calls.get())
            release.countDown(); assertTrue(reported.await(3, TimeUnit.SECONDS)); assertEquals(1, emitted.get())
        } finally { release.countDown(); worker.close() }
        assertEquals(-1, worker.request("0.9.4"))
        val lateEntered = CountDownLatch(1); val lateRelease = CountDownLatch(1); val finished = CountDownLatch(1)
        val late = UpdateCheckRequests(perform = { version ->
            lateEntered.countDown()
            while (true) {
                try { lateRelease.await(); break } catch (_: InterruptedException) { }
            }
            finished.countDown(); UpdateCheck.Result("latest", version)
        }, emit = { _, _ -> emitted.incrementAndGet() })
        late.request("0.9.4"); assertTrue(lateEntered.await(3, TimeUnit.SECONDS)); late.close(); lateRelease.countDown()
        assertTrue(finished.await(3, TimeUnit.SECONDS)); assertEquals(1, emitted.get())
    }
}
