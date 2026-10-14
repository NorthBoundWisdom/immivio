package org.vrpassthroughplayer.plugin

/** Presentation revisions can reuse a paused source without relabeling its identity. */
internal class FramePairGate(private val scope: MediaSessionGate.Scope) {
    data class Identity(
        val decoderId: Int, val logicalSessionId: Int, val generation: Int,
        val frameId: Long, val ptsUs: Long, val formatRevision: Int, val presentationRevision: Long,
        val slotToken: Long, val playbackClockEstimate: Boolean = false
    )

    private var alive = true
    private var format = 1
    private var revision = 1L
    private var presentedFrame = -1L
    private var presentedPts = -1L

    @Synchronized
    fun revisePresentation(): Long {
        check(alive && revision < Long.MAX_VALUE)
        return ++revision
    }

    @Synchronized
    fun setFormat(value: Int) {
        check(alive && value >= format && value > 0)
        if (value != format) {
            revisePresentation(); format = value
        }
    }

    @Synchronized
    fun identify(ticket: DecodedFrameGate.Ticket, token: Long): Identity? {
        if (!alive || ticket.scope != scope || ticket.formatRevision != format || token <= 0 || ticket.frameId < 0 || ticket.ptsUs < 0) return null
        return Identity(
            scope.decoderId,
            scope.logicalSessionId,
            scope.generation,
            ticket.frameId,
            ticket.ptsUs,
            ticket.formatRevision,
            revision,
            token
        )
    }

    @Synchronized
    fun accepts(id: Identity): Boolean = alive && id.decoderId == scope.decoderId &&
            id.logicalSessionId == scope.logicalSessionId && id.generation == scope.generation && id.formatRevision == format &&
            id.presentationRevision == revision && !id.playbackClockEstimate && id.slotToken > 0 && id.frameId >= presentedFrame && id.ptsUs >= presentedPts

    @Synchronized
    fun matchesRuntime(
        id: Identity,
        logicalSession: Long,
        presentationRevision: Long,
        frameId: Long,
        ptsUs: Long
    ): Boolean =
        accepts(id) && logicalSession == id.logicalSessionId.toLong() && presentationRevision == id.presentationRevision && frameId == id.frameId && ptsUs == id.ptsUs

    @Synchronized
    fun presented(id: Identity): Boolean {
        if (!accepts(id)) return false
        presentedFrame = id.frameId; presentedPts = id.ptsUs
        return true
    }

    @Synchronized
    fun close() {
        alive = false
    }
}
