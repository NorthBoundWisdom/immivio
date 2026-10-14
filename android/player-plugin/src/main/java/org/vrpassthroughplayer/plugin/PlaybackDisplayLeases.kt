package org.vrpassthroughplayer.plugin

import android.opengl.EGLContext
import org.json.JSONObject

/** Consumer GL state, distinct from source IO and logical display ordering.
 * Mutations run on the owner GL thread under the session lock. Native retirement
 * must finish before the associated producer lease can be released. */
internal class PlaybackDisplayLeases {
    data class Lease(
        val ticket: DecodedFrameGate.Ticket,
        val pair: JSONObject,
        val producer: Long = 0L
    )

    data class ReadyMask(val pair: JSONObject)

    var renderer = 0L
    var owner: EGLContext? = null
    var borrow = false
    var copyingProducer = 0L
    var copying: Pair<DecodedFrameGate.Ticket, Long>? = null
    var copyingPair: JSONObject? = null
    var pendingSource: JSONObject? = null
    val leases = HashMap<Long, Lease>()
    val alphaUploads = HashMap<Long, ReadyMask>()
    val pairs = HashMap<Long, JSONObject>()
    val retiring = HashSet<Long>()
}
