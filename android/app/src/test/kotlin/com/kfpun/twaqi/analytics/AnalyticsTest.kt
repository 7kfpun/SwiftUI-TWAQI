package com.kfpun.twaqi.analytics

import java.lang.reflect.Modifier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `AnalyticsTests`: every event name Firebase accepts, once, and unchanged. */
class AnalyticsTest {
    private val names: List<String> = Analytics::class.java.declaredFields
        .filter { Modifier.isStatic(it.modifiers) && it.type == String::class.java }
        .map { it.get(null) as String }

    /** Firebase drops a badly named event with no error: up to 40 characters, a letter first. */
    @Test
    fun eventNamesAreValidFirebaseNames() {
        assertTrue(names.size > 20)
        names.forEach { name ->
            assertTrue(name, name.length <= 40)
            assertTrue(name, Regex("^[a-z][a-z0-9_]*$").matches(name))
            assertFalse(name, listOf("firebase_", "google_", "ga_").any(name::startsWith))
        }
    }

    @Test
    fun eventNamesAreUnique() {
        assertEquals(names.size, names.toSet().size)
    }

    @Test
    fun feedbackAndReviewNamesMatchIos() {
        assertEquals("open_feedback_form", Analytics.OPEN_FEEDBACK_FORM)
        assertEquals("submit_feedback", Analytics.SUBMIT_FEEDBACK)
        assertEquals("submit_feedback_failed", Analytics.SUBMIT_FEEDBACK_FAILED)
        assertEquals("review_requested", Analytics.REVIEW_REQUESTED)
        assertEquals("write_review_tapped", Analytics.WRITE_REVIEW_TAPPED)
    }

    /** #77 review: Help's cancel-all and the shortcuts guide, named as iOS `AnalyticsEvent`. */
    @Test
    fun helpNamesMatchIos() {
        assertEquals("favourite_station_all_removed", Analytics.FAVOURITE_STATION_ALL_REMOVED)
        assertEquals("open_shortcuts_guide", Analytics.OPEN_SHORTCUTS_GUIDE)
        assertEquals("open_widget_guide", Analytics.OPEN_WIDGET_GUIDE)
        assertEquals("open_watch_guide", Analytics.OPEN_WATCH_GUIDE)
    }
}
