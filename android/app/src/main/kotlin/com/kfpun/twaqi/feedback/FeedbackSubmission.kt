package com.kfpun.twaqi.feedback

import androidx.annotation.StringRes
import com.kfpun.twaqi.R
import com.kfpun.twaqi.forms.ClientInfo
import com.kfpun.twaqi.forms.FormText
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

/** Where the feedback form was opened from, the `source` of `open_feedback_form` (iOS `FeedbackSource`). */
enum class FeedbackSource(val analyticsName: String) {
    /** Help › Contact us › Feedback / Contact us. */
    HELP("help"),

    /** The "Send feedback" link at the foot of a station's page (FOX-55). */
    STATION_PAGE("station_page")
    ;

    /** Parameters for the `open_feedback_form` event. */
    val openFormEventParameters: Map<String, String> get() = mapOf("source" to analyticsName)

    companion object {
        fun fromAnalyticsName(name: String?): FeedbackSource = entries.firstOrNull { it.analyticsName == name } ?: HELP
    }
}

/**
 * The feedback form as typed (iOS `FeedbackView` state). Required: a rating, the suggestion and a
 * valid email. The other feedback and the name are optional.
 */
data class FeedbackForm(
    val rating: Int? = null,
    val message: String = "",
    val otherFeedback: String = "",
    val interviewInterest: Boolean = false,
    val name: String = "",
    val email: String = ""
) {
    /** Only once something is typed, so an empty form isn't shown in red. */
    val showsEmailError: Boolean
        get() = email.isNotBlank() && !FormText.isValidEmail(email)

    /** Every required field is filled in and the email looks like one. */
    val isComplete: Boolean
        get() = rating != null && FormText.trimmed(message) != null && FormText.isValidEmail(email)

    /** The item to send, or null while [isComplete] is false. */
    fun submission(client: ClientInfo, anonymousId: String?): FeedbackSubmission? {
        val stars = rating ?: return null
        if (!isComplete) return null
        return FeedbackSubmission.make(
            stars,
            message,
            otherFeedback,
            interviewInterest,
            name,
            email,
            client,
            anonymousId
        )
    }
}

/**
 * One item in the Directus `twaqi_feedback` collection (iOS `FeedbackSubmission`). The app only
 * creates items; `status` and `archived` are preset on the server and never sent. Null fields
 * are left out of the JSON.
 */
data class FeedbackSubmission(
    // Set by the app, never shown.
    val platform: String,
    // What the user fills in.
    val rating: Int,
    val message: String,
    val otherFeedback: String?,
    val interviewInterest: Boolean,
    val name: String?,
    val email: String,
    // Filled in by the app, never shown.
    val appVersion: String?,
    val deviceModel: String?,
    val osVersion: String?,
    val locale: String?,
    val metaJson: Map<String, String>?
) {
    /** The Directus JSON, with its field names. */
    fun toJson(): JsonObject = buildJsonObject {
        put("platform", platform)
        put("rating", rating)
        put("message", message)
        otherFeedback?.let { put("other_feedback", it) }
        put("interview_interest", interviewInterest)
        name?.let { put("name", it) }
        put("email", email)
        appVersion?.let { put("app_version", it) }
        deviceModel?.let { put("device_model", it) }
        osVersion?.let { put("os_version", it) }
        locale?.let { put("locale", it) }
        metaJson?.let { meta -> putJsonObject("meta_json") { meta.forEach { (key, value) -> put(key, value) } } }
    }

    /** Parameters for the `submit_feedback` event: no form contents. */
    val submitEventParameters: Map<String, Any>
        get() = mapOf("platform" to platform, "rating" to rating, "interview_interest" to interviewInterest)

    companion object {
        /**
         * Adds the app and device fields, including `platform = android`, to what the user typed.
         * Text is trimmed, blank optional text is left out rather than sent as "", and the rating
         * is kept within 1–5. [anonymousId] is this install's id for `meta_json`.
         */
        fun make(
            rating: Int,
            message: String,
            otherFeedback: String?,
            interviewInterest: Boolean,
            name: String?,
            email: String,
            client: ClientInfo,
            anonymousId: String?
        ): FeedbackSubmission = FeedbackSubmission(
            platform = ClientInfo.PLATFORM,
            rating = rating.coerceIn(1, 5),
            message = FormText.trimmed(message).orEmpty(),
            otherFeedback = FormText.trimmed(otherFeedback),
            interviewInterest = interviewInterest,
            name = FormText.trimmed(name),
            email = FormText.trimmed(email).orEmpty(),
            appVersion = client.appVersion,
            deviceModel = client.deviceModel,
            osVersion = client.osVersion,
            locale = client.locale,
            metaJson = client.meta(anonymousId = anonymousId)
        )

        /**
         * The thank-you's message (iOS `FeedbackView.thankYouMessageKey`): a 4- or 5-star feedback
         * offers Google Play instead; a lower one with an email says we may reply.
         */
        @StringRes
        fun thankYouMessage(offersStoreReview: Boolean, email: String): Int =
            if (!offersStoreReview && email.isNotBlank()) {
                R.string.feedback_sent_message_may_reply
            } else {
                R.string.feedback_sent_message
            }
    }
}
