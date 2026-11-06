package org.vrpassthroughplayer.plugin

import org.junit.Assert.*
import org.junit.Test

class UsbAccessPolicyTest {
    @Test
    fun mountFallbackIsVerifiedPermissionAwareAndReversible() {
        val verified: (String) -> Boolean = { it == "/alternate" }
        var preferredReadable = false
        val readable: (String) -> Boolean = {
            it == "/alternate" || (it == "/preferred" && preferredReadable)
        }
        assertEquals(
            "/alternate",
            LocalStorageVolumePolicy.chooseDirectory(
                "/preferred",
                listOf("/other-disk", "/alternate"),
                true,
                verified,
                readable,
            ),
        )
        assertEquals(
            "/preferred",
            LocalStorageVolumePolicy.chooseDirectory(
                "/preferred",
                listOf("/alternate"),
                false,
                { error("Permission loss cannot probe alternatives") },
                { error("Permission loss cannot probe reads") },
            ),
        )
        preferredReadable = true
        assertEquals(
            "/preferred",
            LocalStorageVolumePolicy.chooseDirectory(
                "/preferred",
                listOf("/alternate"),
                true,
                verified,
                readable,
            ),
        )
        assertNull(
            LocalStorageVolumePolicy.chooseDirectory(
                null,
                listOf("/other-disk"),
                true,
                verified,
                readable,
            )
        )
    }

    @Test
    fun providerFailureNeverFabricatesDeletionOrHardwareRemoval() {
        assertEquals(
            UsbAccessPolicy.DocumentFailure.UNAVAILABLE,
            UsbAccessPolicy.documentFailure(true, false),
        )
        assertEquals(
            UsbAccessPolicy.DocumentFailure.MISSING,
            UsbAccessPolicy.documentFailure(true, true),
        )
        assertEquals(
            UsbAccessPolicy.DocumentFailure.PERMISSION,
            UsbAccessPolicy.documentFailure(false, true),
        )
        assertEquals(
            UsbAccessPolicy.FolderFailure.PERMISSION,
            UsbAccessPolicy.folderFailure(false, true, true),
        )
        assertEquals(
            UsbAccessPolicy.FolderFailure.UNMOUNTED,
            UsbAccessPolicy.folderFailure(true, false, true),
        )
        assertEquals(
            UsbAccessPolicy.FolderFailure.PICO_PROVIDER,
            UsbAccessPolicy.folderFailure(true, true, UsbAccessPolicy.pico("unknown", "PICO")),
        )
    }

    @Test
    fun externalDescriptorAssociationKeepsSourcePrivateAndStopsOnlyItsVolume() {
        val leases = ExternalPlaybackLeases()
        val file = leases.offerOrigin("Film", "fd://5", "file:///storage/1234-5678/Film.mp4") {}
        assertTrue(leases.belongsTo(file, "/storage/1234-5678", "1234-5678"))
        assertFalse(leases.belongsTo(file, "/storage/1234-56780", "other"))
        val document =
            leases.offerOrigin(
                "Film",
                "fd://6",
                "content://com.android.externalstorage.documents/tree/other%3A/document/1234-5678%3AFilm.mp4",
            ) {}
        assertTrue(leases.belongsTo(document, "/storage/1234-5678", "1234-5678"))
        assertFalse(leases.belongsTo(document, "/storage/other", "other"))
        assertFalse(
            UsbAccessPolicy.inside(
                "/storage/1234-5678",
                "/storage/1234-5678/../emulated/0/video.mp4",
            )
        )
        leases.close()
    }
}
