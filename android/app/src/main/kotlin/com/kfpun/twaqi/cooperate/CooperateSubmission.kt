package com.kfpun.twaqi.cooperate

import com.kfpun.twaqi.forms.ClientInfo
import com.kfpun.twaqi.forms.FormText
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

/** What the partner is interested in. [id]s are the Directus `cooperation_type` dropdown choices (iOS `CooperationType`). */
enum class CooperationType(val id: String) {
    ADVERTISING("advertising"),
    DATA_API("data_api"),
    SPONSORSHIP("sponsorship"),
    MEDIA("media"),
    OTHER("other")
}

/**
 * The business partner form as typed (iOS `CooperateView` state). Required: the type, company,
 * name, a valid email and the message. Job title, phone and website are optional.
 */
data class CooperateForm(
    val cooperationType: CooperationType? = null,
    val company: String = "",
    val name: String = "",
    val jobTitle: String = "",
    val email: String = "",
    val phone: String = "",
    val website: String = "",
    val message: String = ""
) {
    /** Only once something is typed, so an empty form isn't shown in red. */
    val showsEmailError: Boolean
        get() = email.isNotBlank() && !FormText.isValidEmail(email)

    /** Every required field is filled in and the email looks like one. */
    val isComplete: Boolean
        get() = cooperationType != null &&
            FormText.trimmed(company) != null &&
            FormText.trimmed(name) != null &&
            FormText.isValidEmail(email) &&
            FormText.trimmed(message) != null

    /** The item to send, or null while [isComplete] is false. */
    fun submission(client: ClientInfo): CooperateSubmission? {
        val type = cooperationType ?: return null
        if (!isComplete) return null
        return CooperateSubmission.make(type, company, name, jobTitle, email, phone, website, message, client)
    }
}

/**
 * One item in the Directus `twaqi_cooperate` collection (iOS `CooperateSubmission`). The app only
 * creates items: it sends `archived: false`, and an enquiry is later soft-deleted by setting
 * `archived` in Directus, never removed. `status` is preset on the server. Null fields are left
 * out of the JSON.
 */
data class CooperateSubmission(
    // What the user fills in.
    val cooperationType: String,
    val company: String,
    val name: String,
    val jobTitle: String?,
    val email: String,
    val phone: String?,
    val website: String?,
    val message: String,
    // Filled in by the app, never shown.
    val platform: String,
    val appVersion: String?,
    val deviceModel: String?,
    val osVersion: String?,
    val locale: String?,
    val metaJson: Map<String, String>?,
    /** Soft-delete flag, always false on create. */
    val archived: Boolean = false
) {
    /** The Directus JSON, with its field names. */
    fun toJson(): JsonObject = buildJsonObject {
        put("cooperation_type", cooperationType)
        put("company", company)
        put("name", name)
        jobTitle?.let { put("job_title", it) }
        put("email", email)
        phone?.let { put("phone", it) }
        website?.let { put("website", it) }
        put("message", message)
        put("platform", platform)
        appVersion?.let { put("app_version", it) }
        deviceModel?.let { put("device_model", it) }
        osVersion?.let { put("os_version", it) }
        locale?.let { put("locale", it) }
        metaJson?.let { meta -> putJsonObject("meta_json") { meta.forEach { (key, value) -> put(key, value) } } }
        put("archived", archived)
    }

    companion object {
        /** Adds the app and device fields to what the user typed, trimming text and dropping blank optional fields. */
        fun make(
            cooperationType: CooperationType,
            company: String,
            name: String,
            jobTitle: String?,
            email: String,
            phone: String?,
            website: String?,
            message: String,
            client: ClientInfo
        ): CooperateSubmission = CooperateSubmission(
            cooperationType = cooperationType.id,
            company = FormText.trimmed(company).orEmpty(),
            name = FormText.trimmed(name).orEmpty(),
            jobTitle = FormText.trimmed(jobTitle),
            email = FormText.trimmed(email).orEmpty(),
            phone = FormText.trimmed(phone),
            website = FormText.trimmed(website),
            message = FormText.trimmed(message).orEmpty(),
            platform = ClientInfo.PLATFORM,
            appVersion = client.appVersion,
            deviceModel = client.deviceModel,
            osVersion = client.osVersion,
            locale = client.locale,
            // No install id: an enquiry carries contact details already.
            metaJson = client.meta(anonymousId = null)
        )
    }
}
