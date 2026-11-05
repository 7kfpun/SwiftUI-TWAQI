package com.kfpun.twaqi.push

import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

/** iOS `PushServiceTests` (requests, payloads, encoding), against a local server. */
class PushApiTest {
    private lateinit var server: MockWebServer

    @Before
    fun setUp() {
        server = MockWebServer().apply { start() }
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    private fun config(url: HttpUrl = server.url("/")) = PushConfig(url, DEVICE_ID, "s3cret")

    // MARK: - Signing (FOX-37 M5)

    @Test
    fun requestSignsWithTheDeviceNotADirectusToken() {
        // The recorded iOS request (`testRequestSignsWithTheDeviceNotADirectusToken`).
        val base = PushConfig.make("https://push.example", DEVICE_ID, "s3cret")!!
        val request = OkHttpPushApi.makeRequest(
            base,
            "PUT",
            "app/v1/stations/105",
            OkHttpPushApi.stationChange(null, StationAlerts(above = 100))
        )
        assertEquals(DEVICE_ID, request.header("X-Device-Id"))
        assertEquals("Bearer s3cret", request.header("Authorization"))
        assertEquals("https://push.example/app/v1/stations/105", request.url.toString())
        assertEquals("PUT", request.method)
        assertEquals("application/json; charset=utf-8", request.body?.contentType().toString())
        val restore = OkHttpPushApi.makeRequest(base, "GET", "app/v1/device")
        // The device is named by its headers; no token goes in the URL.
        assertNull(restore.url.query)
    }

    @Test
    fun requestsReachTheWorkerRoutesSigned() = runTest {
        server.enqueue(MockResponse().setBody("""{"id":42,"created":true}"""))
        server.enqueue(MockResponse().setBody("""{"saved":1,"archived":0}"""))
        server.enqueue(MockResponse().setBody("""{"archived":2}"""))
        server.enqueue(MockResponse().setBody("""{"device":null,"subscriptions":[]}"""))
        val api = OkHttpPushApi(config())

        assertEquals(42, api.upsertDevice(payload()))
        api.reconcile("105", "A12", StationAlerts(above = 120))
        api.archiveAll()
        assertNull(api.restore().device)

        val routes = List(4) { server.takeRequest() }
        assertEquals(
            listOf("PUT /app/v1/device", "PUT /app/v1/stations/105", "POST /app/v1/archive-all", "GET /app/v1/device"),
            routes.map { "${it.method} ${it.path}" }
        )
        routes.forEach {
            assertEquals(DEVICE_ID, it.getHeader("X-Device-Id"))
            assertEquals("Bearer s3cret", it.getHeader("Authorization"))
        }
        val station = Json.parseToJsonElement(routes[1].body.readUtf8()).jsonObject
        assertEquals(120, station.getValue("above").jsonPrimitive.int)
        assertEquals(JsonNull, station["below"])
        assertEquals("A12", station.getValue("site_id").jsonPrimitive.content)
    }

    @Test
    fun serverErrorsCarryTheirStatus() = runTest {
        server.enqueue(MockResponse().setResponseCode(403).setBody("""{"error":"device credentials do not match"}"""))
        try {
            OkHttpPushApi(config()).reconcile("105", null, StationAlerts.OFF)
            fail("expected a server error")
        } catch (e: PushException.Server) {
            assertEquals(403, e.statusCode)
            assertEquals(PushSync.Recovery.NEW_IDENTITY, PushSync.recovery(e))
        }
    }

    @Test
    fun configNeedsAnHttpsPushApi() {
        assertEquals("push.example", PushConfig.make("https://push.example", "d", "s")?.baseUrl?.host)
        assertNull(PushConfig.make("", "d", "s"))
        assertNull(PushConfig.make(null, "d", "s"))
        assertNull(PushConfig.make("http://push.example", "d", "s"))
    }

    // MARK: - The device identity, as the Worker checks it

    @Test
    fun identityMatchesWhatTheWorkerAccepts() {
        // workers/twaqi-push-sender/src/app-api.ts: DEVICE_ID and SECRET.
        val deviceId = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
        val secret = Regex("^[A-Za-z0-9_-]{32,128}$")
        repeat(20) {
            assertTrue(deviceId.matches(PushIdentity.newId()))
            assertTrue(secret.matches(PushIdentity.newSecret()))
        }
    }

    @Test
    fun deviceSecretIsBase64url() {
        // iOS `testDeviceSecretIsBase64url`.
        assertEquals("-__-", PushIdentity.base64url(byteArrayOf(0xfb.toByte(), 0xff.toByte(), 0xfe.toByte())))
        assertEquals(43, PushIdentity.base64url(ByteArray(32)).length)
        assertEquals(43, PushIdentity.newSecret().length)
    }

    @Test
    fun androidDeviceTokenIsAStableHexHashOfTheDeviceId() {
        // Recorded: SHA-256 of the id, as `shasum -a 256` prints it. The Worker wants ^[0-9a-f]{16,200}$.
        assertEquals(
            "57622f6566a831e2551767b89d3ab059d8742bc79eb6dbb2e3190203bb92c7b1",
            PushDevicePayload.androidDeviceToken(DEVICE_ID)
        )
        assertTrue(Regex("^[0-9a-f]{16,200}$").matches(PushDevicePayload.androidDeviceToken(PushIdentity.newId())))
    }

    // MARK: - Payloads

    @Test
    fun devicePayloadEncodesDndAsHourMinute() {
        val body = payload().toJson()
        assertEquals(DEVICE_ID, body.getValue("device_id").jsonPrimitive.content)
        assertEquals(
            PushDevicePayload.androidDeviceToken(DEVICE_ID),
            body.getValue("device_token").jsonPrimitive.content
        )
        assertEquals("android", body.getValue("platform").jsonPrimitive.content)
        assertEquals("fcm:abc", body.getValue("fcm_token").jsonPrimitive.content)
        assertEquals("production", body.getValue("environment").jsonPrimitive.content)
        assertEquals(true, body.getValue("dnd_enabled").jsonPrimitive.boolean)
        assertEquals("22:30", body.getValue("dnd_start").jsonPrimitive.content)
        assertEquals("07:00", body.getValue("dnd_end").jsonPrimitive.content)
        assertEquals("Asia/Taipei", body.getValue("timezone").jsonPrimitive.content)
        assertEquals("1970-01-01T00:00:00Z", body.getValue("last_seen_at").jsonPrimitive.content)
        assertEquals(false, body.getValue("archived").jsonPrimitive.boolean)
        assertEquals(false, body.getValue("is_pro").jsonPrimitive.boolean)
        assertEquals("zh-Hant", body.getValue("locale").jsonPrimitive.content)
        assertFalse(body.containsKey("external_id"))
    }

    @Test
    fun devicePayloadOmitsMissingFcmTokenAndUnknownPermission() {
        val body = payload(fcmToken = null, allowed = null).toJson()
        // Left out, not cleared: a row keeps its last FCM token until a new one.
        assertFalse(body.containsKey("fcm_token"))
        assertFalse(body.containsKey("notifications_allowed"))
        assertEquals(false, payload(allowed = false).toJson().getValue("notifications_allowed").jsonPrimitive.boolean)
        assertEquals("sandbox", payload(debug = true).toJson().getValue("environment").jsonPrimitive.content)
    }

    @Test
    fun profileChangesWithLanguageProNotificationsAndDnd() {
        val base = payload().profile
        assertTrue(base.startsWith("zh-Hant|false|true|"))
        assertFalse(base == payload(isPro = true).profile)
        assertFalse(base == payload(locale = "en").profile)
        assertFalse(base == payload(allowed = false).profile)
        assertFalse(base == payload(dnd = DndWindow(true, LocalTime.of(23, 30), LocalTime.of(7, 0))).profile)
    }

    @Test
    fun stationChangeSendsOffAsNull() {
        val body = OkHttpPushApi.stationChange("A12", StationAlerts(above = 120))
        assertEquals(120, body.getValue("above").jsonPrimitive.int)
        // Off is an explicit null, not a missing key.
        assertEquals(JsonNull, body["below"])
        // Unknown cam: left out.
        assertFalse(OkHttpPushApi.stationChange(null, StationAlerts(below = 30)).containsKey("site_id"))
    }

    @Test
    fun restoreDecodesDeviceAndAlerts() {
        val restored = OkHttpPushApi.parseRestore(
            """{"device":{"id":9,"dnd_enabled":true,"dnd_start":"22:30:00","dnd_end":"07:00"},
               "subscriptions":[
                 {"id":3,"station_id":"42","site_id":null,"metric":"aqi","direction":"below","threshold":30.0,"enabled":true},
                 {"id":4,"station_id":42,"direction":"above","threshold":120,"enabled":true},
                 {"id":5,"station_id":"42","direction":"above","threshold":150,"enabled":true},
                 {"id":6,"station_id":"7","direction":"above","threshold":90,"enabled":false}]}"""
        )
        assertEquals(StoredDevice(9, true, "22:30:00", "07:00"), restored.device)
        assertEquals(LocalTime.of(22, 30), StoredDevice.time(restored.device?.dndStart))
        assertNull(StoredDevice.time("25:00"))
        // Of two rows for one direction, the first wins; a disabled one is no alert.
        assertEquals(
            mapOf("42" to StationAlerts(above = 120, below = 30)),
            StationAlerts.byStation(restored.subscriptions)
        )
    }

    @Test
    fun hourMinuteIsZeroPadded() {
        assertEquals("07:05", PushDevicePayload.hourMinute(LocalTime.of(7, 5)))
        assertEquals("00:00", PushDevicePayload.hourMinute(LocalTime.MIDNIGHT))
    }

    private fun payload(
        fcmToken: String? = "fcm:abc",
        allowed: Boolean? = true,
        isPro: Boolean = false,
        locale: String = "zh-Hant",
        debug: Boolean = false,
        dnd: DndWindow = DndWindow(true, LocalTime.of(22, 30), LocalTime.of(7, 0))
    ) = PushDevicePayload.make(
        deviceId = DEVICE_ID,
        fcmToken = fcmToken,
        dnd = dnd,
        isPro = isPro,
        notificationsAllowed = allowed,
        locale = locale,
        appVersion = "2.0.0",
        debug = debug,
        now = Instant.EPOCH,
        zone = ZoneId.of("Asia/Taipei")
    )

    private companion object {
        const val DEVICE_ID = "6f1c2e7a-0000-4000-8000-000000000001"
    }
}
