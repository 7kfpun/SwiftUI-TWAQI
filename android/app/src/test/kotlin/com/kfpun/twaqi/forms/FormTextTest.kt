package com.kfpun.twaqi.forms

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `FeedbackServiceTests` (the shared `FeedbackSubmission` helpers). */
class FormTextTest {
    @Test
    fun trimmedDropsBlankText() {
        assertEquals("Ann", FormText.trimmed("  Ann \n"))
        assertNull(FormText.trimmed(" \n "))
        assertNull(FormText.trimmed(""))
        assertNull(FormText.trimmed(null))
    }

    @Test
    fun emailCheckIsLoose() {
        assertTrue(FormText.isValidEmail("me@example.com"))
        assertTrue(FormText.isValidEmail(" me@example.com "))
        assertFalse(FormText.isValidEmail(""))
        assertFalse(FormText.isValidEmail("me@example"))
        assertFalse(FormText.isValidEmail("me@@example.com"))
        assertFalse(FormText.isValidEmail("m e@example.com"))
        assertFalse(FormText.isValidEmail("@example.com"))
        assertFalse(FormText.isValidEmail("me@.example.com"))
        assertFalse(FormText.isValidEmail("me@example.com."))
    }

    @Test
    fun failureReasonsAreWordedAsOnIos() {
        assertEquals("offline", FormError.Offline.reason)
        assertEquals("network", FormError.Network.reason)
        assertEquals("notConfigured", FormError.NotConfigured.reason)
        assertEquals("server(statusCode: 403)", FormError.Server(403).reason)
    }
}
