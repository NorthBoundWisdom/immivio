package org.vrpassthroughplayer.plugin

import org.json.JSONObject
import java.nio.ByteBuffer

/** Matting adapter boundary: frame identity remains owned by the effect pipeline.
 * Implementations own independent recurrent states per eye and scout stream.
 * Preparation and inference stay on existing workers. Close invalidates results;
 * implementations must retain any resources still used by an in-flight call.
 */
internal interface MattingRuntime : AutoCloseable {
    val model: ModelDescriptor?
    fun reset(nextGeneration: Long): Boolean
    fun process(generation: Long, frameId: Long, ptsUs: Long, left: ByteBuffer, right: ByteBuffer,
                leftAlpha: ByteBuffer, rightAlpha: ByteBuffer, stream: Int = 0, resetFirst: Boolean = false): JSONObject
    fun processAhb(generation: Long, frameId: Long, ptsUs: Long, buffers: LongArray, alpha: LongArray,
                   stream: Int, resetFirst: Boolean): JSONObject
}
