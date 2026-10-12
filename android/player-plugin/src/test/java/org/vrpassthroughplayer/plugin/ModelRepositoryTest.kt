package org.vrpassthroughplayer.plugin

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.security.MessageDigest

class ModelRepositoryTest {
    private val data = ModelTask.entries.associate { it.asset to "synthetic-${it.key}".toByteArray() }
    private fun manifest(): JSONObject = JSONObject().put("schema_version", 1).put("runtime", ModelRepository.RUNTIME)
        .put("models", JSONArray(ModelTask.entries.map { task ->
            val bytes = data.getValue(task.asset)
            JSONObject().put("task", task.key).put("adapter", task.adapter).put("path", task.asset)
                .put("width", task.width).put("height", task.height).put("id", "public-${task.key}")
                .put("version", "v1").put("license", "test-license").put("source", "synthetic-fixture")
                .put("bytes", bytes.size).put("sha256", MessageDigest.getInstance("SHA-256").digest(bytes)
                    .joinToString("") { "%02x".format(it.toInt() and 255) })
        }))

    private fun repository(json: JSONObject = manifest(), weights: Map<String, ByteArray> = data,
                           opened: (String) -> Unit = {}): ModelRepository = ModelRepository { path ->
        opened(path)
        ByteArrayInputStream(if (path == "ai-models/manifest.json") json.toString().toByteArray() else weights.getValue(path))
    }

    @Test fun publicAndPrivateModelsUseTheSameContractAndKeepTheirIdentity() {
        val public = repository().resolve(ModelTask.MATTING)
        val json = manifest()
        json.getJSONArray("models").getJSONObject(0).put("id", "private-student").put("version", "training-2")
        val custom = repository(json).resolve(ModelTask.MATTING)
        assertEquals("private-student", custom.id)
        assertEquals("training-2", custom.version)
        assertEquals(public.sha256, custom.sha256)
        assertEquals(ModelTask.MATTING, custom.task)
    }

    @Test fun modelsAreVerifiedLazilyOnceWithoutLoadingOtherTasks() {
        val opened = mutableListOf<String>()
        val repository = repository(opened = opened::add)
        repeat(3) { repository.resolve(ModelTask.PHOTO_DEPTH) }
        assertEquals(listOf("ai-models/manifest.json", ModelTask.PHOTO_DEPTH.asset), opened)
    }

    @Test fun sameSizeWrongWeightsAreRejectedAndFailureIsNotCached() {
        val weights = data.toMutableMap()
        val task = ModelTask.MATTING
        weights[task.asset] = ByteArray(weights.getValue(task.asset).size) { 1 }
        val repository = repository(weights = weights)
        assertThrows(IllegalArgumentException::class.java) { repository.resolve(task) }
        weights[task.asset] = data.getValue(task.asset)
        assertEquals("public-matting", repository.resolve(task).id)
    }

    @Test fun missingWeightsDoNotFallBackToAnotherModel() {
        val opened = mutableListOf<String>()
        val repository = repository(weights = data - ModelTask.MATTING.asset, opened = opened::add)
        assertThrows(NoSuchElementException::class.java) { repository.resolve(ModelTask.MATTING) }
        assertEquals(listOf("ai-models/manifest.json", ModelTask.MATTING.asset), opened)
    }

    @Test fun malformedContractsFailBeforeAnyWeightsAreOpened() {
        for ((key, value) in listOf("adapter" to "other", "path" to "../outside.mnn", "width" to 320,
                                   "sha256" to "abcd", "bytes" to 0, "license" to "")) {
            val json = manifest()
            json.getJSONArray("models").getJSONObject(0).put(key, value)
            val opened = mutableListOf<String>()
            assertThrows(IllegalArgumentException::class.java) { repository(json, opened = opened::add).resolve(ModelTask.MATTING) }
            assertEquals(listOf("ai-models/manifest.json"), opened)
        }
    }

    @Test fun incompatibleRuntimeAndDuplicateTasksAreRejected() {
        val wrong = manifest().put("runtime", "other-engine")
        assertThrows(IllegalArgumentException::class.java) { repository(wrong).resolve(ModelTask.MATTING) }
        val duplicate = manifest()
        val entries = duplicate.getJSONArray("models")
        entries.put(1, entries.getJSONObject(0))
        assertThrows(IllegalArgumentException::class.java) { repository(duplicate).resolve(ModelTask.MATTING) }
    }
}
