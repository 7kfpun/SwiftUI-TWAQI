package com.kfpun.twaqi.push

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.math.roundToInt

/** The station page's two alerts (iOS `PushDirection`). */
enum class PushDirection(val wire: String) {
    /** AQI more than the threshold: the "pollution" alert. */
    ABOVE("above"),

    /** AQI less than the threshold: the "cleanliness" alert. */
    BELOW("below")
    ;

    companion object {
        fun fromWire(value: String?): PushDirection? = entries.firstOrNull { it.wire == value }
    }
}

/**
 * A station's two alerts as the push API holds them: a threshold when on, null when off
 * (iOS `StationAlerts`).
 */
data class StationAlerts(val above: Int? = null, val below: Int? = null) {
    val isOff: Boolean get() = above == null && below == null

    fun threshold(direction: PushDirection): Int? = when (direction) {
        PushDirection.ABOVE -> above
        PushDirection.BELOW -> below
    }

    companion object {
        val OFF = StationAlerts()

        /** From the station row's switches: pollution is the above alert, cleanliness the below one. */
        fun from(setting: StationAlertSetting) = StationAlerts(
            above = if (setting.isPollutionNotificationEnabled) setting.pollutionThreshold.roundToInt() else null,
            below = if (setting.isCleanlinessNotificationEnabled) setting.cleanlinessThreshold.roundToInt() else null
        )

        /** Live subscriptions grouped by station. Of several rows for one direction (an earlier race), the first wins. */
        fun byStation(subscriptions: List<PushSubscription>): Map<String, StationAlerts> {
            val result = linkedMapOf<String, StationAlerts>()
            for (item in subscriptions) {
                if (!item.enabled) continue
                val alerts = result[item.stationId] ?: OFF
                result[item.stationId] = when {
                    item.direction == PushDirection.ABOVE && alerts.above == null -> alerts.copy(above = item.threshold)
                    item.direction == PushDirection.BELOW && alerts.below == null -> alerts.copy(below = item.threshold)
                    else -> alerts
                }
            }
            return result.filterValues { !it.isOff }
        }

        // Stored as iOS stores its defaults: station id → {"above": 120, "below": null}.
        fun encodeMap(map: Map<String, StationAlerts>): String = JsonObject(
            map.mapValues { (_, alerts) ->
                JsonObject(
                    mapOf(
                        "above" to (alerts.above?.let(::JsonPrimitive) ?: JsonNull),
                        "below" to (alerts.below?.let(::JsonPrimitive) ?: JsonNull)
                    )
                )
            }
        ).toString()

        /** Anything unreadable reads as no alerts rather than failing (iOS `try?`). */
        fun decodeMap(text: String?): Map<String, StationAlerts> {
            if (text.isNullOrBlank()) return emptyMap()
            return runCatching {
                Json.parseToJsonElement(text).jsonObject.mapValues { (_, value) ->
                    val item = value.jsonObject
                    StationAlerts(item.int("above"), item.int("below"))
                }
            }.getOrDefault(emptyMap())
        }
    }
}

/**
 * A station's two alerts as the station page's switches and sliders edit them (iOS
 * `StationAlertSetting`). The thresholds keep their value while a switch is off, so turning it
 * back on restores the last one. Stored as [StationAlerts].
 */
data class StationAlertSetting(
    val isPollutionNotificationEnabled: Boolean,
    val isCleanlinessNotificationEnabled: Boolean,
    val pollutionThreshold: Double = DEFAULT_POLLUTION_THRESHOLD,
    val cleanlinessThreshold: Double = DEFAULT_CLEANLINESS_THRESHOLD
) {
    val isOn: Boolean get() = isPollutionNotificationEnabled || isCleanlinessNotificationEnabled

    companion object {
        const val DEFAULT_POLLUTION_THRESHOLD = 120.0
        const val DEFAULT_CLEANLINESS_THRESHOLD = 30.0

        val OFF = StationAlertSetting(isPollutionNotificationEnabled = false, isCleanlinessNotificationEnabled = false)

        /** Switches on for each alert that has a threshold; an alert that's off keeps its slider's default. */
        fun from(alerts: StationAlerts) = StationAlertSetting(
            isPollutionNotificationEnabled = alerts.above != null,
            isCleanlinessNotificationEnabled = alerts.below != null,
            pollutionThreshold = alerts.above?.toDouble() ?: DEFAULT_POLLUTION_THRESHOLD,
            cleanlinessThreshold = alerts.below?.toDouble() ?: DEFAULT_CLEANLINESS_THRESHOLD
        )
    }
}

/**
 * One alert, a `twaqi_push_subscriptions` item as the push API returns it (iOS
 * `PushSubscription`). A station has at most one live (not archived) item per direction.
 */
data class PushSubscription(
    val id: Int? = null,
    val stationId: String,
    val siteId: String?,
    val direction: PushDirection,
    val threshold: Int,
    val enabled: Boolean
) {
    companion object {
        /** Tolerant like iOS: a numeric station id or threshold reads too. Null when unusable. */
        fun parse(element: JsonElement): PushSubscription? = runCatching {
            val item = element.jsonObject
            val station = item["station_id"]?.jsonPrimitive?.contentOrNull ?: return null
            val direction = PushDirection.fromWire(item["direction"]?.jsonPrimitive?.contentOrNull) ?: return null
            val threshold = item["threshold"]?.jsonPrimitive?.doubleOrNull?.roundToInt() ?: return null
            PushSubscription(
                id = item.int("id"),
                stationId = station,
                siteId = item["site_id"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.contentOrNull,
                direction = direction,
                threshold = threshold,
                enabled = item["enabled"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.booleanOrNull ?: false
            )
        }.getOrNull()
    }
}

private fun JsonObject.int(key: String): Int? = this[key]?.takeIf { it !is JsonNull }?.jsonPrimitive?.intOrNull
