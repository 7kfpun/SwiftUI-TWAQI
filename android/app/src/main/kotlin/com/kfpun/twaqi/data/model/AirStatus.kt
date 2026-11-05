package com.kfpun.twaqi.data.model

import androidx.annotation.StringRes
import com.kfpun.twaqi.R

/**
 * Air-quality band of a reading (iOS `AirStatuses`), with the colours every marker, badge and
 * chart bar uses. Colours are `0xRRGGBB`.
 */
enum class AirStatus(
    val key: String,
    val color: Int,
    val foregroundColor: Int,
    @param:StringRes val label: Int,
    @param:StringRes val generalPublicGuidance: Int?,
    @param:StringRes val sensitiveGroupGuidance: Int?
) {
    GOOD(
        "good",
        0x009866,
        WHITE,
        R.string.airstatus_good,
        R.string.airstatus_general_public_guidance_good,
        R.string.airstatus_sensitive_group_guidance_good
    ),
    MODERATE(
        "moderate",
        0xFEDE33,
        BLACK,
        R.string.airstatus_moderate,
        R.string.airstatus_general_public_guidance_moderate,
        R.string.airstatus_sensitive_group_guidance_moderate
    ),
    UNHEALTHY_FOR_SENSITIVE_GROUP(
        "unhealthyforsensitivegroup",
        0xFE9833,
        BLACK,
        R.string.airstatus_unhealthyforsensitivegroup,
        R.string.airstatus_general_public_guidance_unhealthyforsensitivegroup,
        R.string.airstatus_sensitive_group_guidance_unhealthyforsensitivegroup
    ),
    UNHEALTHY(
        "unhealthy",
        0xCC0033,
        WHITE,
        R.string.airstatus_unhealthy,
        R.string.airstatus_general_public_guidance_unhealthy,
        R.string.airstatus_sensitive_group_guidance_unhealthy
    ),
    VERY_UNHEALTHY(
        "veryunhealthy",
        0x660098,
        WHITE,
        R.string.airstatus_veryunhealthy,
        R.string.airstatus_general_public_guidance_veryunhealthy,
        R.string.airstatus_sensitive_group_guidance_veryunhealthy
    ),
    HAZARDOUS(
        "hazardous",
        0x7E2200,
        WHITE,
        R.string.airstatus_hazardous,
        R.string.airstatus_general_public_guidance_hazardous,
        R.string.airstatus_sensitive_group_guidance_hazardous
    ),

    /** No reading (0, negative, or outside every band). Grey, and no face image. */
    UNKNOWN("unknown", 0x676767, WHITE, R.string.airstatus_unknown, null, null)
    ;

    /** Drawable name of the face, `status_good`; there is none for [UNKNOWN]. */
    val imageName: String? get() = if (this == UNKNOWN) null else "status_$key"

    val hasFaceImage: Boolean get() = this != UNKNOWN

    /** A band: `from` inclusive, `until` exclusive. */
    data class Band(val from: Double, val until: Double, val status: AirStatus) {
        operator fun contains(value: Double): Boolean = value >= from && value < until
    }

    companion object {
        /** The six real bands, for legends. Never [UNKNOWN]. */
        val showAllCases: List<AirStatus> =
            listOf(GOOD, MODERATE, UNHEALTHY_FOR_SENSITIVE_GROUP, UNHEALTHY, VERY_UNHEALTHY, HAZARDOUS)

        /** Colour bands for each index, lowest first; the same thresholds as iOS `AirStatuses.bands`. */
        val bands: Map<AirIndexType, List<Band>> = mapOf(
            AirIndexType.AQI to bands(1.0, 51.0, 101.0, 151.0, 201.0, 301.0, 1000.0),
            AirIndexType.PM25 to bands(0.1, 15.5, 35.5, 54.5, 150.5, 250.5, 5005.0),
            AirIndexType.PM10 to bands(1.0, 55.0, 126.0, 255.0, 355.0, 425.0, 6050.0),
            AirIndexType.O3 to bands(1.0, 55.0, 125.0, 165.0, 205.0, 405.0, 605.0),
            AirIndexType.CO to bands(0.1, 4.5, 9.5, 12.5, 15.5, 30.5, 50.5),
            AirIndexType.SO2 to bands(1.0, 36.0, 76.0, 186.0, 305.0, 605.0, 1005.0),
            AirIndexType.NO2 to bands(1.0, 54.0, 101.0, 361.0, 650.0, 1250.0, 2050.0)
        )

        fun of(type: AirIndexType, value: Double): AirStatus =
            bands[type]?.firstOrNull { value in it }?.status ?: UNKNOWN

        private fun bands(vararg edges: Double): List<Band> =
            showAllCases.mapIndexed { index, status -> Band(edges[index], edges[index + 1], status) }
    }
}

private const val WHITE = 0xFFFFFF
private const val BLACK = 0x000000
