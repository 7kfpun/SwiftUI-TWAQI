package com.kfpun.twaqi.feedback

import com.kfpun.twaqi.R
import com.kfpun.twaqi.cooperate.testClient
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `FeedbackServiceTests` (the item) and `StoreReviewTests` (the thank-you). */
class FeedbackSubmissionTest {
    @Test
    fun makeTrimsTextAndDropsBlankOptionals() {
        val made = feedback(otherFeedback = " \n ", name = "  ", email = " me@example.com ")

        assertEquals("Add PM1", made.message)
        assertEquals("me@example.com", made.email)
        assertNull(made.otherFeedback)
        assertNull(made.name)
        assertTrue(made.interviewInterest)
    }

    @Test
    fun makeFillsHiddenDeviceFieldsAndPlatform() {
        val made = feedback()

        assertEquals("android", made.platform)
        assertEquals("2.0.0", made.appVersion)
        assertEquals("Google Pixel 9", made.deviceModel)
        assertEquals("16", made.osVersion)
        assertEquals("zh-TW", made.locale)
        assertEquals("android", made.metaJson?.get("app_platform"))
        assertEquals("com.kfpun.twaqi", made.metaJson?.get("bundle_id"))
        assertEquals("install-1", made.metaJson?.get("anonymous_id"))
    }

    @Test
    fun makeClampsRating() {
        assertEquals(5, feedback(rating = 9).rating)
        assertEquals(1, feedback(rating = 0).rating)
    }

    @Test
    fun encodesDirectusFieldNames() {
        val json = feedback(otherFeedback = "Widget is slow", name = "Ann").toJson()

        assertEquals(
            setOf(
                "platform", "rating", "message", "other_feedback", "interview_interest",
                "name", "email", "app_version", "device_model", "os_version", "locale", "meta_json"
            ),
            json.keys
        )
        assertEquals(4, json["rating"]?.jsonPrimitive?.int)
        assertTrue(json["interview_interest"]!!.jsonPrimitive.boolean)
        assertEquals("Widget is slow", json["other_feedback"]?.jsonPrimitive?.content)
        assertNotNull(json["meta_json"]?.jsonObject)
    }

    @Test
    fun omitsBlankOptionalsAndServerFields() {
        val json = feedback().toJson()

        assertNull(json["other_feedback"])
        assertNull(json["name"])
        // Set on the server; the app never sends them.
        assertNull(json["status"])
        assertNull(json["archived"])
    }

    @Test
    fun formNeedsRatingMessageAndValidEmail() {
        val complete = FeedbackForm(rating = 3, message = "More stations", email = "me@example.com")
        assertTrue(complete.isComplete)

        assertFalse(complete.copy(rating = null).isComplete)
        assertFalse(complete.copy(message = " \n ").isComplete)
        assertFalse(complete.copy(email = "").isComplete)
        assertFalse(complete.copy(email = "me@example").isComplete)
        assertNull(complete.copy(rating = null).submission(testClient, null))
        assertEquals("More stations", complete.submission(testClient, null)?.message)
    }

    @Test
    fun emailErrorShowsOnlyOnceSomethingIsTyped() {
        assertFalse(FeedbackForm(email = "").showsEmailError)
        assertFalse(FeedbackForm(email = "  ").showsEmailError)
        assertTrue(FeedbackForm(email = "me@").showsEmailError)
        assertFalse(FeedbackForm(email = "me@example.com").showsEmailError)
    }

    @Test
    fun submitEventCarriesNoFormContents() {
        assertEquals(
            mapOf("platform" to "android", "rating" to 4, "interview_interest" to true),
            feedback().submitEventParameters
        )
    }

    @Test
    fun openFormEventParametersNameTheEntryPoint() {
        assertEquals(mapOf("source" to "help"), FeedbackSource.HELP.openFormEventParameters)
        assertEquals(mapOf("source" to "station_page"), FeedbackSource.STATION_PAGE.openFormEventParameters)
        assertEquals(FeedbackSource.STATION_PAGE, FeedbackSource.fromAnalyticsName("station_page"))
        assertEquals(FeedbackSource.HELP, FeedbackSource.fromAnalyticsName(null))
    }

    @Test
    fun thankYouSaysWeMayReplyOnlyWithoutTheStoreOffer() {
        assertEquals(
            R.string.feedback_sent_message_may_reply,
            FeedbackSubmission.thankYouMessage(offersStoreReview = false, email = "a@b.co")
        )
        assertEquals(
            R.string.feedback_sent_message,
            FeedbackSubmission.thankYouMessage(offersStoreReview = true, email = "a@b.co")
        )
        assertEquals(
            R.string.feedback_sent_message,
            FeedbackSubmission.thankYouMessage(offersStoreReview = false, email = "  ")
        )
    }
}

internal fun feedback(
    rating: Int = 4,
    otherFeedback: String? = null,
    name: String? = null,
    email: String = "me@example.com"
) = FeedbackSubmission.make(
    rating = rating,
    message = "  Add PM1 \n",
    otherFeedback = otherFeedback,
    interviewInterest = true,
    name = name,
    email = email,
    client = testClient,
    anonymousId = "install-1"
)
