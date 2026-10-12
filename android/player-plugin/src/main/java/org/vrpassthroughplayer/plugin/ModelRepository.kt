package org.vrpassthroughplayer.plugin

import org.json.JSONObject
import java.io.InputStream
import java.security.MessageDigest

/** A build selects one model per task. Adapters define tensor semantics, not model authorship.
 * Matting has dynamic allowlisted profiles; depth keeps the current fixed GPU bridge shapes.
 */
internal enum class ModelTask(val key: String, val adapter: String, val asset: String, val width: Int, val height: Int) {
    MATTING("matting", "rvm-rgba-recurrent-v1", "rvm-mnn/rvm.mnn", 0, 0),
    VIDEO_DEPTH("video-depth", "relative-inverse-depth-v1", "depth-mnn/depth.mnn", 252, 140),
    PHOTO_DEPTH("photo-depth", "relative-inverse-depth-v1", "depth-mnn/photo_depth.mnn", 518, 518),
}

internal data class ModelDescriptor(
    val task: ModelTask, val id: String, val version: String, val path: String,
    val bytes: Long, val sha256: String, val license: String, val source: String,
)

/** APK assets are immutable. Validate metadata once, then hash each model on its first use
 * on a preparation/inference worker. Neither weights nor Activity objects are retained.
 * No fallback to another model or an unverified legacy asset on failure.
 */
internal class ModelRepository(private val open: (String) -> InputStream) {
    private val descriptors: Map<ModelTask, ModelDescriptor> by lazy {
        val json = open("ai-models/manifest.json").bufferedReader(Charsets.UTF_8).use { JSONObject(it.readText()) }
        require(json.get("schema_version") == 1 && json.get("runtime") == RUNTIME) { "Unsupported model pack/runtime ABI" }
        val models = json.getJSONArray("models")
        require(models.length() == ModelTask.entries.size) { "A model pack needs one model per task" }
        val result = linkedMapOf<ModelTask, ModelDescriptor>()
        val ids = hashSetOf<String>()
        for (i in 0 until models.length()) {
            val model = models.getJSONObject(i)
            val task = ModelTask.entries.singleOrNull { it.key == model.getString("task") }
                ?: error("Unknown model task")
            require(task !in result && model.getString("adapter") == task.adapter &&
                model.getString("path") == task.asset && model.get("width") == task.width &&
                model.get("height") == task.height) { "Model adapter/path/dimensions differ for ${task.key}" }
            fun text(key: String): String {
                val value = model.get(key)
                require(value is String && value.isNotBlank()) { "Missing model $key" }
                return value
            }
            val size = model.get("bytes")
            require(size is Int || size is Long) { "Model size must be an integer" }
            val descriptor = ModelDescriptor(task, text("id"), text("version"), text("path"), (size as Number).toLong(),
                text("sha256"), text("license"), text("source"))
            require(ids.add(descriptor.id) && descriptor.bytes > 0 && descriptor.sha256.matches(Regex("[0-9a-f]{64}"))) {
                "Invalid model ID, size or SHA256"
            }
            result[task] = descriptor
        }
        result
    }
    private val verified = hashSetOf<ModelTask>()

    @Synchronized fun resolve(task: ModelTask): ModelDescriptor {
        val model = descriptors.getValue(task)
        if (task !in verified) {
            val sha = MessageDigest.getInstance("SHA-256")
            var bytes = 0L
            open(model.path).use { input ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (count == 0) continue
                    bytes = Math.addExact(bytes, count.toLong())
                    require(bytes <= model.bytes) { "Model size differs: ${model.id}" }
                    sha.update(buffer, 0, count)
                }
            }
            val hash = sha.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
            require(bytes == model.bytes && hash == model.sha256) { "Model size/hash differs: ${model.id}" }
            verified.add(task)
        }
        return model
    }

    companion object { const val RUNTIME = "mnn-3.6.1-vrpp-opencl-v1" }
}
