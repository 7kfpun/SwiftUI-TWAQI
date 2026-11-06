package com.kfpun.twaqi.push

import com.kfpun.twaqi.data.remote.ApiClient
import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.security.MessageDigest
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/** Why a push API call failed (iOS `PushError`). */
sealed class PushException(message: String) : Exception(message) {
    /** `PUSH_API_URL` is missing, or the Keystore wouldn't hold the identity. */
    class NotConfigured : PushException("push API not configured")

    class Offline : PushException("offline")

    class Network : PushException("network error")

    class Server(val statusCode: Int) : PushException("push API answered $statusCode")
}

/**
 * Where the push API is and who this install is. The app holds no Directus token for push: each
 * request names this install's device id and carries its secret (FOX-37 M5).
 */
data class PushConfig(val baseUrl: HttpUrl, val deviceId: String, val secret: String) {
    companion object {
        /** Null unless [baseUrl] is a non-empty https URL (iOS `PushService.Config.make`). */
        fun make(baseUrl: String?, deviceId: String, secret: String): PushConfig? {
            val url = baseUrl?.trim()?.takeIf(String::isNotEmpty)?.toHttpUrlOrNull() ?: return null
            if (url.scheme != "https") return null
            return PushConfig(url, deviceId, secret)
        }
    }
}

/**
 * The app's side of a `twaqi_push_devices` item (iOS `PushDevicePayload`): everything but the
 * sender's bookkeeping.
 *
 * @property deviceToken iOS sends its APNs token here. Android has none, but the Worker requires
 *   a hex `device_token` (16–200 chars) and keys a row's uniqueness on it, so Android sends
 *   [androidDeviceToken], a SHA-256 of the install's device id: stable, unique and never an
 *   APNs token. The sender addresses [fcmToken] only. Until the Worker takes an optional
 *   `device_token` and stores `platform`, this shim stays (follow-up to FOX-57).
 */
data class PushDevicePayload(
    val deviceId: String,
    val deviceToken: String,
    /** The FCM registration token: what the sender addresses. Null until Messaging has one; left out rather than cleared. */
    val fcmToken: String?,
    /** An APNs notion; debug builds say sandbox, release builds production, as on iOS. */
    val environment: String,
    val appVersion: String?,
    /** The app's language, "zh-Hant" or "en": the sender writes each alert in it. */
    val locale: String,
    val isPro: Boolean,
    /** Whether Android shows the app's notifications; null before the user was asked (Android 13+). */
    val notificationsAllowed: Boolean?,
    val lastSeenAt: String,
    val dndEnabled: Boolean,
    /** "HH:mm", wall-clock time in [timezone]. */
    val dndStart: String,
    val dndEnd: String,
    val timezone: String
) {
    /**
     * What, besides the tokens, makes the row out of date when it changes: language, Pro,
     * notifications allowed, and the do-not-disturb window with its time zone. Saved only after
     * a write succeeds, so a failed one is retried on the next sync, even after a relaunch.
     */
    val profile: String
        get() = listOf(
            locale,
            isPro.toString(),
            notificationsAllowed?.toString() ?: "",
            dndEnabled.toString(),
            dndStart,
            dndEnd,
            timezone
        ).joinToString("|")

    fun toJson(): JsonObject {
        val fields = linkedMapOf<String, JsonElement>(
            "device_id" to JsonPrimitive(deviceId),
            "device_token" to JsonPrimitive(deviceToken),
            // The Worker drops this today (it isn't one of its device fields); sent so the row
            // says so once the Worker and Directus take it.
            "platform" to JsonPrimitive(PLATFORM)
        )
        fcmToken?.let { fields["fcm_token"] = JsonPrimitive(it) }
        fields["environment"] = JsonPrimitive(environment)
        appVersion?.let { fields["app_version"] = JsonPrimitive(it) }
        fields["locale"] = JsonPrimitive(locale)
        fields["is_pro"] = JsonPrimitive(isPro)
        notificationsAllowed?.let { fields["notifications_allowed"] = JsonPrimitive(it) }
        fields["last_seen_at"] = JsonPrimitive(lastSeenAt)
        fields["dnd_enabled"] = JsonPrimitive(dndEnabled)
        fields["dnd_start"] = JsonPrimitive(dndStart)
        fields["dnd_end"] = JsonPrimitive(dndEnd)
        fields["timezone"] = JsonPrimitive(timezone)
        // A device seen again is alive.
        fields["archived"] = JsonPrimitive(false)
        return JsonObject(fields)
    }

    companion object {
        const val PLATFORM = "android"

        private val HOUR_MINUTE: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")

        fun make(
            deviceId: String,
            fcmToken: String?,
            dnd: DndWindow,
            isPro: Boolean,
            notificationsAllowed: Boolean?,
            locale: String,
            appVersion: String?,
            debug: Boolean,
            now: Instant = Instant.now(),
            zone: ZoneId = ZoneId.systemDefault()
        ) = PushDevicePayload(
            deviceId = deviceId,
            deviceToken = androidDeviceToken(deviceId),
            fcmToken = fcmToken?.takeIf(String::isNotEmpty),
            environment = if (debug) "sandbox" else "production",
            appVersion = appVersion,
            locale = locale,
            isPro = isPro,
            notificationsAllowed = notificationsAllowed,
            // iOS ISO8601DateFormatter: whole seconds, Z.
            lastSeenAt = DateTimeFormatter.ISO_INSTANT.format(now.truncatedTo(ChronoUnit.SECONDS)),
            dndEnabled = dnd.enabled,
            dndStart = hourMinute(dnd.start),
            dndEnd = hourMinute(dnd.end),
            timezone = zone.id
        )

        fun hourMinute(time: LocalTime): String = time.format(HOUR_MINUTE)

        /** See [deviceToken]: lowercase hex SHA-256 of the device id. */
        fun androidDeviceToken(deviceId: String): String =
            MessageDigest.getInstance("SHA-256").digest(deviceId.toByteArray(Charsets.UTF_8))
                .joinToString("") { "%02x".format(it) }
    }
}

/** This install's row as a restore reads it: its id and do-not-disturb window. */
data class StoredDevice(val id: Int, val dndEnabled: Boolean?, val dndStart: String?, val dndEnd: String?) {
    companion object {
        /** "HH:mm" or "HH:mm:ss" (Directus may add seconds); null when unreadable. */
        fun time(text: String?): LocalTime? {
            val parts = text?.split(":")?.mapNotNull(String::toIntOrNull) ?: return null
            if (parts.size < 2 || parts[0] !in 0..23 || parts[1] !in 0..59) return null
            return LocalTime.of(parts[0], parts[1])
        }
    }
}

/** What a restore reads: this install's row (null when it has none) and its live alerts. */
data class RestoredDevice(val device: StoredDevice?, val subscriptions: List<PushSubscription>)

/** The push Worker's `/app/v1` API (iOS `PushService`). Swapped for a fake in tests. */
interface PushApi {
    /** Creates or updates this device's row; returns its id. */
    suspend fun upsertDevice(payload: PushDevicePayload): Int

    /** The row this install's id and secret own, with its live alerts. */
    suspend fun restore(): RestoredDevice

    /** One station's alerts: on updates (or makes) its rows, off archives them. */
    suspend fun reconcile(stationId: String, siteId: String?, alerts: StationAlerts)

    /** Help's "cancel all": archives every live alert of this device. */
    suspend fun archiveAll()
}

/** [PushApi] over OkHttp. Nothing is hard-deleted: an alert switched off is archived by the Worker. */
class OkHttpPushApi(private val config: PushConfig, private val http: OkHttpClient = defaultClient()) : PushApi {
    override suspend fun upsertDevice(payload: PushDevicePayload): Int {
        val body = send(makeRequest(config, "PUT", "app/v1/device", payload.toJson()))
        return Json.parseToJsonElement(body).jsonObject.getValue("id").jsonPrimitive.int
    }

    override suspend fun restore(): RestoredDevice = parseRestore(send(makeRequest(config, "GET", "app/v1/device")))

    override suspend fun reconcile(stationId: String, siteId: String?, alerts: StationAlerts) {
        send(makeRequest(config, "PUT", "app/v1/stations/$stationId", stationChange(siteId, alerts)))
    }

    override suspend fun archiveAll() {
        send(makeRequest(config, "POST", "app/v1/archive-all"))
    }

    private suspend fun send(request: Request): String = withContext(Dispatchers.IO) {
        val response = try {
            http.newCall(request).execute()
        } catch (e: UnknownHostException) {
            throw PushException.Offline()
        } catch (e: ConnectException) {
            throw PushException.Offline()
        } catch (e: SocketTimeoutException) {
            throw PushException.Network()
        } catch (e: IOException) {
            throw PushException.Network()
        }
        response.use {
            if (!it.isSuccessful) throw PushException.Server(it.code)
            it.body?.string().orEmpty()
        }
    }

    companion object {
        private val JSON_TYPE = "application/json".toMediaType()

        fun defaultClient(): OkHttpClient = ApiClient.defaultHttpClient().newBuilder()
            .callTimeout(20, TimeUnit.SECONDS)
            .build()

        /**
         * The request as iOS `PushService.makeRequest` builds it: the device is named by
         * `X-Device-Id` and proved by `Authorization: Bearer <secret>`; no token goes in the URL.
         */
        fun makeRequest(config: PushConfig, method: String, path: String, body: JsonObject? = null): Request {
            val url = config.baseUrl.newBuilder().addPathSegments(path).build()
            return Request.Builder()
                .url(url)
                .header("X-Device-Id", config.deviceId)
                .header("Authorization", "Bearer ${config.secret}")
                .header("Accept", "application/json")
                // OkHttp wants a body on POST and PUT; iOS sends `archive-all` without one.
                .method(method, body?.toString()?.toRequestBody(JSON_TYPE) ?: emptyBody(method))
                .build()
        }

        private fun emptyBody(method: String) =
            if (method == "POST" || method == "PUT") ByteArray(0).toRequestBody(null) else null

        /** `{ site_id?, above, below }`: off is an explicit null, not a missing key; an unknown cam is left out. */
        fun stationChange(siteId: String?, alerts: StationAlerts): JsonObject {
            val fields = linkedMapOf<String, JsonElement>()
            siteId?.let { fields["site_id"] = JsonPrimitive(it) }
            fields["above"] = alerts.above?.let(::JsonPrimitive) ?: JsonNull
            fields["below"] = alerts.below?.let(::JsonPrimitive) ?: JsonNull
            return JsonObject(fields)
        }

        fun parseRestore(text: String): RestoredDevice {
            val root = Json.parseToJsonElement(text).jsonObject
            val device = root["device"]?.takeIf { it !is JsonNull }?.jsonObject?.let { item ->
                val id = item["id"]?.jsonPrimitive?.intOrNull ?: return@let null
                StoredDevice(
                    id = id,
                    dndEnabled = item["dnd_enabled"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.booleanOrNull,
                    dndStart = item["dnd_start"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.contentOrNull,
                    dndEnd = item["dnd_end"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.contentOrNull
                )
            }
            val subscriptions = root["subscriptions"]?.takeIf { it !is JsonNull }?.jsonArray
                ?.mapNotNull(PushSubscription::parse).orEmpty()
            return RestoredDevice(device, subscriptions)
        }
    }
}
