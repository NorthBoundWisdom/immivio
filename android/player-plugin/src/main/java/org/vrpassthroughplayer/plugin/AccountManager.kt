package org.vrpassthroughplayer.plugin

import android.app.Activity
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.SystemClock
import org.json.JSONArray
import org.json.JSONObject
import java.net.Inet4Address
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/** In-process account workflows, independent of Android windows and the Godot render loop.
 * A snapshot survives focus loss; cancelled sessions cannot commit late authentication results. */
internal class AccountManager(private val host: () -> Activity?) {
    private val ids = AtomicInteger()
    private val worker = Executors.newFixedThreadPool(2) { Thread(it, "PlayerAccount") }
    @Volatile
    private var session: Session? = null
    @Volatile
    private var closed = false
    private fun context(): Context = host()?.applicationContext ?: error("Activity unavailable")

    private class Session(
        val id: Int,
        val kind: String,
        val provider: String,
        val accountId: String
    ) : AccountSessionGuard() {
        val inputs =
            listOf("name", "base", "username", "password").associateWith { AccountInput() }
        @Volatile
        var state = "form"
        var error = ""
        var busy = false
        var revision = 0
        var old: MediaServerAccount? = null
        @Volatile
        var http: MediaServerHttp? = null
        @Volatile
        var discovery: MediaServerDiscovery? = null
        var result = JSONObject()
        @Volatile
        var plex: PlexAuth? = null
        var plexPin: PlexAuth.Pin? = null
        var plexExpiresAt = 0L
        val plexClientId = UUID.randomUUID().toString()
        var plexServers = emptyList<PlexAuth.Server>()
        var plexToken: String? = null
        fun value(key: String) = inputs.getValue(key).text()
        fun set(key: String, text: String) {
            inputs.getValue(key).clear(); inputs.getValue(key).append(text)
        }
    }

    @Synchronized
    fun open(kind: String, provider: String, accountId: String, raw: String): Int {
        if (closed || kind !in setOf(
                "server",
                "discover"
            ) || raw.length > 4096
        ) return -1
        if (kind == "server" && provider !in setOf(
                "emby",
                "jellyfin",
                "stash",
                "xbvr",
                "plex"
            )
        ) return -1
        cancel(session?.id ?: 0)
        val s = Session(ids.incrementAndGet(), kind, provider, accountId)
        session = s
        try {
            val app = context()
            val data = if (raw.isEmpty()) JSONObject() else JSONObject(raw)
            if (kind == "server") {
                s.old = if (accountId.isEmpty()) null else MediaServerStore.get(app, accountId)
                require(s.old == null || s.old!!.provider == provider)
                s.set("name", s.old?.name ?: data.optString("name", providerName(provider)))
                s.set(
                    "base",
                    s.old?.base ?: data.optString("base", if (provider == "plex") "" else "http://")
                )
                s.set("username", s.old?.username ?: "")
            }
            if (kind == "discover") task(s) { discover(s, app) }
        } catch (_: Exception) {
            s.error = "Account settings unavailable"; s.revision++
        }
        return s.id
    }

    fun accounts(kind: String): String = try {
        val app = context()
        require(kind == "server")
        JSONArray().apply {
            MediaServerStore.accounts(app).forEach {
                put(
                    it.json().put("username", it.username).put("has_password", it.key.isNotEmpty())
                )
            }
        }.toString()
    } catch (_: Exception) {
        "null"
    }

    fun snapshot(id: Int): String {
        val s = session?.takeIf { it.id == id && !it.cancelled } ?: return "{}"
        synchronized(s) {
            val pairingExpired =
                s.provider == "plex" && s.state == "plex_link" && s.plexToken == null &&
                        s.plexPin != null && SystemClock.elapsedRealtime() >= s.plexExpiresAt
            val fields = JSONObject()
            for ((name, input) in s.inputs) fields.put(
                name,
                if (name == "password") "" else input.text()
            )
            val value = JSONObject().put("id", id).put("state", s.state).put("busy", s.busy)
                .put("error", if (pairingExpired) "Pairing code expired" else s.error)
                .put("pairing_expired", pairingExpired)
                .put("revision", s.revision).put("fields", fields)
                .put("password_length", s.inputs.getValue("password").length)
                .put("has_password", s.old?.key?.isNotEmpty() == true)
                .put("result", s.result)
                .put("editing_account", s.accountId.isNotEmpty())
            return value.toString()
        }
    }

    fun input(id: Int, field: String, action: String, text: String) {
        val s = session?.takeIf { it.id == id } ?: return
        if (action == "paste") {
            val activity = host() ?: return
            synchronized(s) {
                if (s.cancelled || s.busy || field !in s.inputs) return
                s.busy = true; s.revision++
            }
            activity.runOnUiThread {
                try {
                    val clipboard =
                        activity.getSystemService(Context.CLIPBOARD_SERVICE) as? android.content.ClipboardManager
                    val value = clipboard?.primaryClip?.takeIf { it.itemCount > 0 }
                        ?.getItemAt(0)?.text?.toString()?.trimEnd('\r', '\n').orEmpty()
                    commit(s) {
                        if (value.length > 2048) s.error = "Input too long"
                        else if (value.isNotEmpty() && value.none { it == '\u0000' || it == '\n' || it == '\r' }) {
                            s.inputs.getValue(field).clear(); s.inputs.getValue(field).append(value)
                        }
                    }
                } catch (_: Exception) {
                    synchronized(s) { if (!s.cancelled) s.error = "Account settings unavailable" }
                } finally {
                    synchronized(s) { s.busy = false; s.revision++ }
                }
            }
            return
        }
        synchronized(s) {
            if (s.cancelled || s.busy || text.length > 4096) return
            val input = s.inputs[field] ?: return
            when (action) {
                "append" -> input.append(text)
                "backspace" -> input.backspace()
                "clear" -> input.clear()
                "replace" -> if (text.none { it == '\u0000' || it == '\n' || it == '\r' }) {
                    input.clear(); input.append(text)
                }
            }
            s.revision++
        }
    }

    fun action(id: Int, action: String, raw: String) {
        val s = session?.takeIf { it.id == id && !it.cancelled } ?: return
        if (raw.length > 4096) return
        val data = runCatching { if (raw.isEmpty()) JSONObject() else JSONObject(raw) }.getOrNull()
            ?: return
        task(s) {
            val app = context()
            when (action) {
                "plex_authorize" -> {
                    require(s.kind == "server" && s.provider == "plex"); authorizePlex(s)
                }

                "plex_confirm" -> {
                    require(s.kind == "server" && s.provider == "plex" && s.state == "plex_link"); confirmPlex(
                        s,
                        app
                    )
                }

                "plex_select" -> {
                    require(s.kind == "server" && s.provider == "plex" && s.state == "plex_servers");
                    val server = s.plexServers.firstOrNull { it.id == data.optString("server_id") }
                        ?: throw MediaServerFailure("Video unavailable")
                    connectPlex(s, app, server)
                }

                "save_server" -> {
                    require(s.kind == "server"); saveServer(s, app)
                }

                else -> error("Invalid action")
            }
        }
    }

    private fun task(s: Session, work: () -> Unit): Boolean {
        synchronized(s) {
            if (closed || s.cancelled || s.busy) return false
            s.busy = true; s.error = ""; s.revision++
        }
        try {
            worker.execute {
                if (s.cancelled || closed) return@execute
                try {
                    work()
                } catch (e: Exception) {
                    synchronized(s) {
                        if (!s.cancelled) {
                            if (e is MediaServerFailure && e.httpStatus > 0) s.result.put(
                                "http_status",
                                e.httpStatus
                            )
                            s.error = when (e) {
                                is MediaServerFailure -> e.code

                                else -> "Unable to connect. Please retry."
                            }
                        }
                    }
                } finally {
                    synchronized(s) { s.busy = false; s.revision++ }
                }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            synchronized(s) { s.busy = false; s.revision++ }
            return false
        }
        return true
    }

    private fun commit(s: Session, block: () -> Unit) = s.commitSession {
        check(!s.cancelled && session === s && !closed)
        block()
    }

    private fun saveServer(s: Session, app: Context) {
        val old = s.old
        val candidate = MediaServerAccount(
            old?.id ?: UUID.randomUUID().toString(),
            s.value("name").trim().take(80).ifBlank { providerName(s.provider) },
            MediaServerAccount.address(s.value("base")),
            "",
            s.provider,
            old?.userId ?: "",
            s.value("username").trim()
        )
        val secret = s.value("password")
        val sameLogin =
            old != null && old.base == candidate.base && old.username == candidate.username && secret.isEmpty()
        if (s.provider == "plex") mediaRequire(sameLogin, "Server authentication required")
        val authenticated = if (s.provider in setOf("emby", "jellyfin")) {
            if (sameLogin) candidate.copy(key = old!!.key) else MediaServerHttp(candidate).use { http ->
                s.http = http; check(!s.cancelled); EmbyClient(
                candidate,
                http
            ).login(candidate.username, secret)
            }
        } else candidate.copy(key = if (sameLogin) old!!.key else secret)
        MediaServerHttp(authenticated).use { http ->
            s.http = http; check(!s.cancelled); mediaClient(authenticated, http).probe()
        }
        s.http = null
        commit(s) {
            synchronized(MediaServerStore) {
                check(old == null || MediaServerStore.get(app, old.id) == old)
                MediaServerStore.save(app, authenticated); s.state =
                "done"; s.inputs.values.forEach { it.clear() }
            }
        }
    }

    private fun authorizePlex(s: Session) {
        s.plex?.close()
        s.plexToken = null; s.plexPin = null
        val auth = PlexAuth(s.old?.id ?: s.plexClientId)
        s.plex = auth
        check(!s.cancelled)
        val pin = auth.createPin()
        commit(s) {
            s.plexPin = pin; s.plexExpiresAt = SystemClock.elapsedRealtime() + pin.expiresIn * 1000L
            s.plexServers = emptyList(); s.state = "plex_link"
            s.result = JSONObject().put("code", pin.code).put("link", "plex.tv/link")
        }
    }

    private fun confirmPlex(s: Session, app: Context) {
        val auth = s.plex ?: throw MediaServerFailure("Pairing code expired")
        val token = s.plexToken ?: run {
            val pin = s.plexPin ?: throw MediaServerFailure("Pairing code expired")
            mediaRequire(SystemClock.elapsedRealtime() < s.plexExpiresAt, "Pairing code expired")
            val approved = auth.confirm(pin)
            // Retain approval only in this native session if fetching resources needs a retry.
            commit(s) { s.plexToken = approved }
            approved
        }
        val servers = auth.servers(token)
        mediaRequire(servers.isNotEmpty(), "No Plex servers available")
        commit(s) {
            s.plexToken = null; s.plexServers = servers; s.state = "plex_servers"
            s.result = JSONObject().put("servers", JSONArray(servers.map { it.publicJson() }))
        }
        val manual = s.value("base").trim()
        if (manual.isNotBlank()) {
            val identity = auth.identify(manual)
            val server = servers.firstOrNull { it.id == identity }
                ?: throw MediaServerFailure("Server authentication required")
            connectPlex(
                s,
                app,
                server,
                listOf(PlexAuth.Connection(MediaServerAccount.address(manual), true, false))
            )
        } else if (servers.size == 1) connectPlex(s, app, servers.single())
    }

    private fun connectPlex(
        s: Session, app: Context, server: PlexAuth.Server,
        connections: List<PlexAuth.Connection> = server.connections
    ) {
        val auth = s.plex ?: throw MediaServerFailure("Server authentication required")
        val manager = app.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val subnets =
            manager.activeNetwork?.let { manager.getLinkProperties(it) }?.linkAddresses.orEmpty()
                .filter { it.address is Inet4Address }
                .map { MediaServerDiscovery.Subnet(it.address.hostAddress!!, it.prefixLength) }
        val targets = PlexAuth.preferredConnections(connections, subnets)
            .filter { !server.httpsRequired || it.base.startsWith("https://") }
        val name = s.value("name").trim().take(80).ifBlank { server.name }
        val account = PlexConnectionSelector.select(
            targets,
            { s.cancelled || closed },
            { auth.cancelProbes() }) { connection ->
            mediaRequire(
                auth.identify(connection.base, 2500, 3000) == server.id,
                "Wrong server type"
            )
            auth.probe(
                MediaServerAccount(
                    s.old?.id ?: s.plexClientId,
                    name,
                    connection.base,
                    server.token,
                    "plex",
                    server.id
                )
            )
        }
        commit(s) {
            synchronized(MediaServerStore) {
                check(s.old == null || MediaServerStore.get(app, s.old!!.id) == s.old)
                MediaServerStore.save(app, account); s.state = "done"; s.result = JSONObject()
                s.plexServers = emptyList(); s.plexPin =
                null; s.inputs.values.forEach { it.clear() }
            }
        }
        auth.close()
    }

    private fun discover(s: Session, app: Context) {
        val manager = app.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = manager.activeNetwork ?: throw MediaServerFailure("Connect to Wi-Fi")
        val caps = manager.getNetworkCapabilities(network)
        val address =
            manager.getLinkProperties(network)?.linkAddresses?.firstOrNull { it.address is Inet4Address && it.address.isSiteLocalAddress }
        mediaRequire(
            caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true && address != null,
            "Connect to Wi-Fi"
        )
        val scanner =
            MediaServerDiscovery { network.openConnection(it) as java.net.HttpURLConnection }
        s.discovery = scanner
        val lock =
            (app.getSystemService(Context.WIFI_SERVICE) as WifiManager).createMulticastLock("PlayerAccountDiscovery")
        commit(s) { s.state = "discover"; s.result = JSONObject().put("servers", JSONArray()) }
        try {
            lock.acquire()
            scanner.scan(
                MediaServerDiscovery.Subnet(
                    address!!.address.hostAddress!!,
                    address.prefixLength
                )
            ) { found ->
                commit(s) {
                    mediaRequire(manager.activeNetwork == network, "Network changed. Search again.")
                    s.result.getJSONArray("servers").put(
                        JSONObject().put("name", found.name).put("base", found.address)
                            .put("provider", found.provider)
                    )
                    s.revision++
                }
            }
            mediaRequire(manager.activeNetwork == network, "Network changed. Search again.")
        } finally {
            scanner.close(); if (lock.isHeld) lock.release(); s.discovery = null
        }
    }

    @Synchronized
    fun cancel(id: Int) {
        val s = session?.takeIf { it.id == id } ?: return
        s.cancelSession {
            s.inputs.values.forEach { it.clear() }; s.result = JSONObject()
        }
        s.plexServers = emptyList(); s.plexPin = null; s.plexToken = null
        s.http?.close(); s.discovery?.close(); s.plex?.close()
        session = null
    }

    @Synchronized
    fun close() {
        closed = true; cancel(session?.id ?: 0); worker.shutdownNow()
    }

    private fun providerName(provider: String) = mapOf(
        "stash" to "Stash",
        "emby" to "Emby",
        "jellyfin" to "Jellyfin",
        "xbvr" to "XBVR",
        "plex" to "Plex"
    )[provider] ?: provider
}
