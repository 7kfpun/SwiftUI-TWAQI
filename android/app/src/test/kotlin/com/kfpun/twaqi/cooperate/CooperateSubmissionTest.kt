package com.kfpun.twaqi.cooperate

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `CooperateServiceTests` (the submission), plus the form's validation from `CooperateView`. */
class CooperateSubmissionTest {
    @Test
    fun makeTrimsTextAndDropsBlankOptionals() {
        val made = submission(jobTitle = "  ", phone = "\n", website = " ")

        assertEquals("Fox Co.", made.company)
        assertEquals("Ann", made.name)
        assertEquals("ann@example.com", made.email)
        assertEquals("Embed AQI on our site", made.message)
        assertEquals("data_api", made.cooperationType)
        assertNull(made.jobTitle)
        assertNull(made.phone)
        assertNull(made.website)
    }

    @Test
    fun makeFillsHiddenDeviceFieldsWithPlatformAndroid() {
        val made = submission()

        assertEquals("android", made.platform)
        assertEquals("2.0.0", made.appVersion)
        assertEquals("Google Pixel 9", made.deviceModel)
        assertEquals("16", made.osVersion)
        assertEquals("zh-TW", made.locale)
        assertEquals("android", made.metaJson?.get("app_platform"))
        assertEquals("com.kfpun.twaqi", made.metaJson?.get("bundle_id"))
        assertEquals("Asia/Taipei", made.metaJson?.get("time_zone"))
        // Not needed for a business enquiry, and not in the privacy footer.
        assertNull(made.metaJson?.get("anonymous_id"))
    }

    @Test
    fun encodesDirectusFieldNames() {
        val json = submission(jobTitle = "CEO", phone = "02-1234-5678", website = "fox.example").toJson()

        assertEquals(
            setOf(
                "cooperation_type", "company", "name", "job_title", "email", "phone", "website", "message",
                "platform", "app_version", "device_model", "os_version", "locale", "meta_json", "archived"
            ),
            json.keys
        )
        assertEquals("CEO", json.string("job_title"))
        assertTrue(json["meta_json"] is JsonObject)
        assertEquals("phone", json["meta_json"]!!.jsonObject.string("device_idiom"))
    }

    @Test
    fun omitsBlankOptionalsAndSendsNotArchived() {
        val json = submission().toJson()

        assertNull(json["job_title"])
        assertNull(json["phone"])
        assertNull(json["website"])
        // Created live; archiving is the soft delete, done in Directus.
        assertEquals(JsonPrimitive(false), json["archived"])
        // Preset on the server; the app never sends it.
        assertNull(json["status"])
    }

    @Test
    fun typeIdsMatchDirectusChoices() {
        assertEquals(
            listOf("advertising", "data_api", "sponsorship", "media", "other"),
            CooperationType.entries.map { it.id }
        )
    }

    @Test
    fun completeFormCanBeSent() {
        assertTrue(completeForm.isComplete)
        assertNotNull(completeForm.submission(testClient))
        // Job title, phone and website are optional.
        assertTrue(completeForm.copy(jobTitle = "", phone = "", website = "").isComplete)
    }

    @Test
    fun everyRequiredFieldIsNeeded() {
        val incomplete = listOf(
            completeForm.copy(cooperationType = null),
            completeForm.copy(company = "  "),
            completeForm.copy(name = ""),
            completeForm.copy(email = ""),
            completeForm.copy(email = "ann@example"),
            completeForm.copy(message = " \n ")
        )
        incomplete.forEach { form ->
            assertFalse("$form", form.isComplete)
            assertNull("$form", form.submission(testClient))
        }
    }

    @Test
    fun emailErrorShowsOnlyOnceSomethingIsTyped() {
        assertFalse(CooperateForm().showsEmailError)
        assertFalse(CooperateForm(email = "   ").showsEmailError)
        assertTrue(CooperateForm(email = "ann@").showsEmailError)
        assertFalse(CooperateForm(email = "ann@example.com").showsEmailError)
    }

    @Test
    fun submissionFromFormTrimsWhatWasTyped() {
        val made = completeForm.copy(company = " Fox Co. ", phone = "  ").submission(testClient)!!

        assertEquals("advertising", made.cooperationType)
        assertEquals("Fox Co.", made.company)
        assertNull(made.phone)
    }

    private fun JsonObject.string(key: String) = get(key)?.jsonPrimitive?.content
}
