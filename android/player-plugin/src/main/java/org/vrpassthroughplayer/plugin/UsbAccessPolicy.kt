package org.vrpassthroughplayer.plugin

/** Mount/provider policy adapted from upstream UsbClaimPolicy; no raw USB driver claims. */
internal object UsbAccessPolicy {
    enum class FolderFailure(val code: String, val message: String) {
        PERMISSION("STORAGE_PERMISSION_NEEDED", "All files access needed"),
        UNMOUNTED(
            "STORAGE_NOT_MOUNTED",
            "Storage device is no longer mounted. Reconnect and retry.",
        ),
        PROVIDER(
            "STORAGE_PROVIDER_UNAVAILABLE",
            "Storage provider unavailable. Check system storage settings and retry.",
        ),
        PICO_PROVIDER(
            "PICO_STORAGE_PROVIDER_UNAVAILABLE",
            "PICO storage unavailable. Check system storage settings, reconnect, then retry.",
        ),
    }

    enum class DocumentFailure(val code: String) {
        PERMISSION("LOCAL_DOCUMENT_PERMISSION_LOST"),
        MISSING("LOCAL_DOCUMENT_MISSING"),
        UNAVAILABLE("LOCAL_DOCUMENT_PROVIDER_UNAVAILABLE"),
    }

    fun pico(manufacturer: String?, brand: String?) =
        manufacturer.orEmpty().contains("pico", true) || brand.orEmpty().contains("pico", true)

    fun folderFailure(permission: Boolean, mounted: Boolean, pico: Boolean): FolderFailure =
        when {
            !permission -> FolderFailure.PERMISSION
            !mounted -> FolderFailure.UNMOUNTED
            pico -> FolderFailure.PICO_PROVIDER
            else -> FolderFailure.PROVIDER
        }

    fun documentFailure(authorized: Boolean, missingConfirmed: Boolean): DocumentFailure =
        when {
            !authorized -> DocumentFailure.PERMISSION
            missingConfirmed -> DocumentFailure.MISSING
            else -> DocumentFailure.UNAVAILABLE
        }

    fun inside(root: String, path: String): Boolean {
        fun normalized(value: String): String? = runCatching {
            if (!value.startsWith('/')) return null
            java.net.URI(null, null, value, null).normalize().path.trimEnd('/').takeIf {
                it.isNotEmpty() && ".." !in it.split('/')
            }
        }
            .getOrNull()
        val base = normalized(root) ?: return false
        val value = normalized(path) ?: return false
        return value == base || value.startsWith("$base/")
    }
}
