package com.kfpun.twaqi.feedback

import com.kfpun.twaqi.forms.FormError
import com.kfpun.twaqi.forms.SubmitResult
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.Buffer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

/** iOS `FeedbackServiceTests` (the request), against a local server. */
class OkHttpFeedbackRepositoryTest {
    private lateinit var server: MockWebServer

    @Before
    fun setUp() {
        server = MockWebServer().apply { start() }
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun requestPostsToCollectionWithBearerToken() {
        val request = OkHttpFeedbackRepository.makeRequest("https://cms.example.com", "test-token", feedback())!!

        assertEquals("POST", request.method)
        assertEquals("https://cms.example.com/items/twaqi_feedback", request.url.toString())
        assertEquals("Bearer test-token", request.header("Authorization"))
        assertEquals("application/json", request.body?.contentType()?.toString()?.substringBefore(';'))
        val body = Buffer().also { request.body!!.writeTo(it) }.readUtf8()
        assertEquals("Add PM1", Json.parseToJsonElement(body).jsonObject["message"]?.jsonPrimitive?.content)
    }

    @Test
    fun requestNeedsUrlAndToken() {
        assertNull(OkHttpFeedbackRepository.makeRequest("https://cms.example.com", "", feedback()))
        assertNull(OkHttpFeedbackRepository.makeRequest("https://cms.example.com", null, feedback()))
        assertNull(OkHttpFeedbackRepository.makeRequest("", "t", feedback()))
    }

    @Test
    fun createOnlyTokenAnswerCountsAsSent() = runTest {
        // A create-only token can't read the item back, so Directus answers 204.
        server.enqueue(MockResponse().setResponseCode(204))

        assertEquals(SubmitResult.Sent, repository().submit(feedback()))

        val recorded = server.takeRequest()
        assertEquals("/items/twaqi_feedback", recorded.path)
        assertEquals("Bearer test-token", recorded.getHeader("Authorization"))
        val json = Json.parseToJsonElement(recorded.body.readUtf8()).jsonObject
        assertEquals("android", json["platform"]?.jsonPrimitive?.content)
        assertEquals(4, json["rating"]?.jsonPrimitive?.int)
    }

    @Test
    fun serverErrorIsReportedWithItsStatus() = runTest {
        server.enqueue(MockResponse().setResponseCode(403))

        assertEquals(SubmitResult.Failed(FormError.Server(403)), repository().submit(feedback()))
    }

    @Test
    fun missingConfigIsNotConfigured() = runTest {
        val result = OkHttpFeedbackRepository(baseUrl = "", token = "").submit(feedback())

        assertEquals(SubmitResult.Failed(FormError.NotConfigured), result)
    }

    private fun repository() = OkHttpFeedbackRepository(baseUrl = server.url("/").toString(), token = "test-token")
}
