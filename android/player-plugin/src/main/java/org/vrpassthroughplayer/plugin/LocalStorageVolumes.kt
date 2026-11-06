package org.vrpassthroughplayer.plugin

import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.storage.StorageManager
import android.provider.Settings
import java.io.File
import org.json.JSONArray
import org.json.JSONObject

internal object LocalStorageVolumePolicy {
    fun mounted(state: String) = state == "mounted" || state == "mounted_ro"

    fun removable(removable: Boolean, primary: Boolean, emulated: Boolean) =
        removable && !primary && !emulated

    fun legacyCandidates(uuid: String?, appDirectories: List<String>): List<String> {
        val candidates = mutableListOf<String>()
        if (uuid != null && Regex("[A-Za-z0-9-]{1,64}").matches(uuid))
            candidates.add("/storage/$uuid")
        for (path in appDirectories) {
            val marker = path.indexOf("/Android/data/")
            if (marker > 0) candidates.add(path.substring(0, marker))
        }
        return candidates.distinct()
    }

    fun chooseDirectory(
        preferred: String?,
        fallbacks: List<String>,
        permission: Boolean,
        verified: (String) -> Boolean,
        readable: (String) -> Boolean,
    ): String? {
        if (preferred != null && (!permission || readable(preferred))) return preferred
        val valid = fallbacks.distinct().filter(verified)
        return if (!permission) preferred ?: valid.firstOrNull()
        else valid.firstOrNull(readable) ?: preferred ?: valid.firstOrNull()
    }

    // Third-party apps cannot call StorageManager.unmount. These open the system's own UI.
    fun openEjectSettings(launch: (String) -> Unit): Boolean {
        for (action in
            listOf(
                Settings.ACTION_MEMORY_CARD_SETTINGS,
                Settings.ACTION_INTERNAL_STORAGE_SETTINGS,
            )) {
            try {
                launch(action)
                return true
            } catch (_: Exception) {}
        }
        return false
    }
}

internal object LocalStorageVolumes {
    fun roots(context: Context): JSONArray {
        val result = JSONArray()
        val manager = context.getSystemService(StorageManager::class.java) ?: return result
        for (volume in manager.storageVolumes) {
            if (!LocalStorageVolumePolicy.mounted(volume.state)) continue
            val preferred =
                if (Build.VERSION.SDK_INT >= 30) volume.directory
                else if (volume.isPrimary) Environment.getExternalStorageDirectory() else null
            val permission =
                LocalStoragePermissions.allFiles(
                    Build.VERSION.SDK_INT,
                    Build.VERSION.SDK_INT >= 30 && Environment.isExternalStorageManager(),
                    Build.VERSION.SDK_INT < 30 && Environment.isExternalStorageLegacy(),
                    context.checkSelfPermission(
                        android.Manifest.permission.READ_EXTERNAL_STORAGE
                    ) == android.content.pm.PackageManager.PERMISSION_GRANTED,
                )
            val candidates =
                LocalStorageVolumePolicy.legacyCandidates(
                    volume.uuid,
                    context.getExternalFilesDirs(null).filterNotNull().take(32).map {
                        it.absolutePath
                    },
                )
            val selected =
                LocalStorageVolumePolicy.chooseDirectory(
                    preferred?.absolutePath,
                    candidates,
                    permission,
                    verified = {
                        runCatching { manager.getStorageVolume(File(it)) == volume }
                            .getOrDefault(false)
                    },
                    readable = { File(it).isDirectory && File(it).canRead() },
                )
            val directory = selected?.let(::File)
            if (directory == null) continue
            result.put(
                JSONObject()
                    .put("id", directory.absolutePath)
                    .put("title", volume.getDescription(context))
                    .put("container", true)
                    .put("volume", true)
                    .put("uuid", volume.uuid ?: "")
                    .put(
                        "removable",
                        LocalStorageVolumePolicy.removable(
                            volume.isRemovable,
                            volume.isPrimary,
                            volume.isEmulated,
                        ),
                    )
                    .put("read_only", volume.state == Environment.MEDIA_MOUNTED_READ_ONLY)
                    .put("readable", directory.canRead())
                    .put("permission_needed", !permission && !directory.canRead())
            )
        }
        return result
    }
}
