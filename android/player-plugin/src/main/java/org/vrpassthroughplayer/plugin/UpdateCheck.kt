package org.vrpassthroughplayer.plugin

import org.json.JSONObject
import java.io.Closeable
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/** No IO occurs on construction. Only a user-initiated check invokes this transport. */
internal class UpdateCheck(
    private val endpoint: URI = URI(ENDPOINT),
    private val connectTimeoutMs: Int = 5000,
    private val readTimeoutMs: Int = 10000
) : Closeable {
    data class Result(val state: String, val version: String, val tag: String = "") {
        fun json(): String = JSONObject().put("state", state).put("version", version).put("tag", tag).toString()
    }
    @Volatile private var closed = false
    private var active: HttpURLConnection? = null
    init {
        // Only the injected test seam may use HTTP, and then only explicit loopback.
        require(endpoint == URI(ENDPOINT) || (endpoint.scheme == "http" && endpoint.host in setOf("127.0.0.1", "localhost", "[::1]")))
        require(endpoint.rawUserInfo == null && endpoint.fragment == null)
    }
    fun check(version: String): Result {
        if (!localVersion.matches(version) || version.length > 128) return Result("invalid_response", version.take(128))
        var connection: HttpURLConnection? = null
        return try {
            val c = endpoint.toURL().openConnection() as HttpURLConnection
            connection = c
            synchronized(this) {
                if (closed) { c.disconnect(); throw IOException("Closed") }
                active = c
            }
            c.requestMethod = "GET"
            c.connectTimeout = connectTimeoutMs; c.readTimeout = readTimeoutMs
            c.instanceFollowRedirects = false; c.useCaches = false
            // This request has no connection to the account store or its credentials.
            c.setRequestProperty("User-Agent", "Immivio/$version")
            c.setRequestProperty("Accept", "application/vnd.github+json")
            when (val status = c.responseCode) {
                403, 429 -> Result("rate_limited", version)
                200 -> {
                    require(c.contentLengthLong <= MAX_BYTES) { "Response too large" }
                    val bytes = c.inputStream.use { input ->
                        val output = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            if (count == 0) continue
                            require(count <= MAX_BYTES - output.size()) { "Response too large" }
                            output.write(buffer, 0, count)
                        }
                        output.toByteArray()
                    }
                    val data = JSONObject(bytes.toString(Charsets.UTF_8))
                    val tag = data.getString("tag_name")
                    val url = releaseUrl(tag) ?: throw IllegalArgumentException("Invalid tag")
                    require(data.getString("html_url") == url)
                    require(!data.optBoolean("draft") && !data.optBoolean("prerelease"))
                    Result(if (newer(tag.removePrefix("v"), version)) "available" else "latest", version, tag)
                }
                in 300..399 -> Result("invalid_response", version) // Never follow any redirect, even within the host.
                else -> Result(if (status >= 500) "network_error" else "invalid_response", version)
            }
        } catch (_: IOException) { Result("network_error", version) }
        catch (_: Exception) { Result("invalid_response", version) }
        finally {
            synchronized(this) { if (active === connection) active = null }
            connection?.disconnect()
        }
    }
    @Synchronized override fun close() { closed = true; active?.disconnect(); active = null }
    companion object {
        const val ENDPOINT = "https://api.github.com/repos/NorthBoundWisdom/immivio/releases/latest"
        const val MAX_BYTES = 256 * 1024
        private val localVersion = Regex("[0-9]+[.][0-9]+[.][0-9]+")
        private val tagVersion = Regex("v[0-9]+[.][0-9]+[.][0-9]+")
        fun releaseUrl(tag: String): String? = if (tag.length <= MAX_BYTES && tagVersion.matches(tag))
            "https://github.com/NorthBoundWisdom/immivio/releases/tag/$tag" else null
        /** Compare numeric components without machine-integer overflow, including leading zeros. */
        fun newer(remote: String, local: String): Boolean {
            require(localVersion.matches(remote) && localVersion.matches(local))
            for ((a, b) in remote.split('.').zip(local.split('.'))) {
                val left = a.trimStart('0').ifEmpty { "0" }; val right = b.trimStart('0').ifEmpty { "0" }
                val compared = if (left.length != right.length) left.length.compareTo(right.length) else left.compareTo(right)
                if (compared != 0) return compared > 0
            }
            return false
        }
    }
}

/** One request at a time; repeat clicks never enqueue work or replace a running callback. */
internal class UpdateCheckRequests(
    private val transport: UpdateCheck = UpdateCheck(),
    private val perform: (String) -> UpdateCheck.Result = transport::check,
    private val emit: (Int, String) -> Unit
) : Closeable {
    private val worker = ThreadPoolExecutor(1, 1, 0, TimeUnit.MILLISECONDS, ArrayBlockingQueue(1),
        { Thread(it, "ImmivioUpdateCheck").apply { isDaemon = true } })
    private var closed = false
    private var pending = 0
    private var serial = 0
    @Synchronized fun request(version: String): Int {
        if (closed || pending != 0 || version.length > 128) return -1
        val id = ++serial
        pending = id
        try {
            worker.execute {
                val result = runCatching { perform(version) }.getOrElse { UpdateCheck.Result("network_error", version) }
                synchronized(this) {
                    if (!closed && pending == id) {
                        pending = 0
                        emit(id, result.json())
                    }
                }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) { pending = 0; return -1 }
        return id
    }
    @Synchronized override fun close() {
        closed = true; pending = 0; transport.close(); worker.shutdownNow()
    }
}
