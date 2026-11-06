package com.kfpun.twaqi.cooperate

import com.kfpun.twaqi.forms.FormError
import com.kfpun.twaqi.forms.SubmitResult
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.Buffer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

/** iOS `CooperateServiceTests` (the request), against a local server. */
class OkHttpCooperateRepositoryTest {
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
    fun requestPostsToCollectionWithCooperateToken() {
        val request = OkHttpCooperateRepository.makeRequest(
            "https://cms.example.com",
            "coop-token",
            "feedback-token",
            submission()
        )!!

        assertEquals("POST", request.method)
        assertEquals("https://cms.example.com/items/twaqi_cooperate", request.url.toString())
        assertEquals("Bearer coop-token", request.header("Authorization"))
        assertEquals("application/json", request.body?.contentType()?.toString()?.substringBefore(';'))
        val body = Buffer().also { request.body!!.writeTo(it) }.readUtf8()
        assertEquals("Fox Co.", Json.parseToJsonElement(body).jsonObject["company"]?.jsonPrimitive?.content)
    }

    @Test
    fun requestFallsBackToFeedbackToken() {
        listOf(null, "", "  ").forEach { cooperateToken ->
            val request = OkHttpCooperateRepository.makeRequest(
                "https://cms.example.com",
                cooperateToken,
                "feedback-token",
                submission()
            )
            assertEquals("Bearer feedback-token", request?.header("Authorization"))
        }
    }

    @Test
    fun requestNeedsUrlAndSomeToken() {
        assertNull(OkHttpCooperateRepository.makeRequest("https://cms.example.com", null, "", submission()))
        assertNull(OkHttpCooperateRepository.makeRequest("", "t", "t", submission()))
        assertNull(OkHttpCooperateRepository.makeRequest("not a url", "t", "t", submission()))
    }

    @Test
    fun createOnlyTokenAnswerCountsAsSent() = runTest {
        // A create-only token can't read the item back, so Directus answers 204.
        server.enqueue(MockResponse().setResponseCode(204))

        assertEquals(SubmitResult.Sent, repository().submit(submission()))

        val recorded = server.takeRequest()
        assertEquals("/items/twaqi_cooperate", recorded.path)
        assertEquals("Bearer coop-token", recorded.getHeader("Authorization"))
        val json = Json.parseToJsonElement(recorded.body.readUtf8()).jsonObject
        assertEquals("android", json["platform"]?.jsonPrimitive?.content)
        assertEquals("data_api", json["cooperation_type"]?.jsonPrimitive?.content)
    }

    @Test
    fun serverErrorIsReportedWithItsStatus() = runTest {
        server.enqueue(MockResponse().setResponseCode(403))

        assertEquals(SubmitResult.Failed(FormError.Server(403)), repository().submit(submission()))
    }

    @Test
    fun missingConfigIsNotConfigured() = runTest {
        val result = OkHttpCooperateRepository(
            baseUrl = "",
            cooperateToken = "",
            feedbackToken = ""
        ).submit(submission())

        assertEquals(SubmitResult.Failed(FormError.NotConfigured), result)
    }

    @Test
    fun droppedConnectionIsANetworkError() = runTest {
        server.enqueue(MockResponse().setSocketPolicy(okhttp3.mockwebserver.SocketPolicy.DISCONNECT_AT_START))

        val result = repository().submit(submission())

        assertNotNull(result as? SubmitResult.Failed)
        assertEquals(FormError.Network, (result as SubmitResult.Failed).error)
    }

    private fun repository() = OkHttpCooperateRepository(
        baseUrl = server.url("/").toString(),
        cooperateToken = "coop-token",
        feedbackToken = ""
    )
}
