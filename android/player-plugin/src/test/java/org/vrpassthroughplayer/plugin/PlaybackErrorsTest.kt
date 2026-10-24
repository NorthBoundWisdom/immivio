package org.vrpassthroughplayer.plugin
import org.junit.Assert.*
import org.junit.Test
class PlaybackErrorsTest {
    @Test fun secretsAreRedactedWithoutLosingTheReason() {
        val value = PlaybackErrors.safe("HTTP 403 https://user:pass@nas/media?token=secret token=secret2 password:hello")
        assertTrue(value.contains("HTTP 403"))
        for (secret in listOf("user", "pass@", "nas", "secret", "hello")) assertFalse(value.contains(secret))
    }
}
