package com.kfpun.twaqi.data.model

import androidx.annotation.StringRes
import com.kfpun.twaqi.R

/**
 * Air-quality band of a reading (iOS `AirStatuses`), with the colours every marker, badge and
 * chart bar uses. Colours are `0xRRGGBB`. The bands and colours are [AirLevel]'s (`:core`), shared
 * with the Wear OS app (FOX-62); this adds the phone's text.
 */
enum class AirStatus(
    val level: AirLevel,
    @param:StringRes val label: Int,
    @param:StringRes val generalPublicGuidance: Int?,
    @param:StringRes val sensitiveGroupGuidance: Int?
) {
    GOOD(
        AirLevel.GOOD,
        R.string.airstatus_good,
        R.string.airstatus_general_public_guidance_good,
        R.string.airstatus_sensitive_group_guidance_good
    ),
    MODERATE(
        AirLevel.MODERATE,
        R.string.airstatus_moderate,
        R.string.airstatus_general_public_guidance_moderate,
        R.string.airstatus_sensitive_group_guidance_moderate
    ),
    UNHEALTHY_FOR_SENSITIVE_GROUP(
        AirLevel.UNHEALTHY_FOR_SENSITIVE_GROUP,
        R.string.airstatus_unhealthyforsensitivegroup,
        R.string.airstatus_general_public_guidance_unhealthyforsensitivegroup,
        R.string.airstatus_sensitive_group_guidance_unhealthyforsensitivegroup
    ),
    UNHEALTHY(
        AirLevel.UNHEALTHY,
        R.string.airstatus_unhealthy,
        R.string.airstatus_general_public_guidance_unhealthy,
        R.string.airstatus_sensitive_group_guidance_unhealthy
    ),
    VERY_UNHEALTHY(
        AirLevel.VERY_UNHEALTHY,
        R.string.airstatus_veryunhealthy,
        R.string.airstatus_general_public_guidance_veryunhealthy,
        R.string.airstatus_sensitive_group_guidance_veryunhealthy
    ),
    HAZARDOUS(
        AirLevel.HAZARDOUS,
        R.string.airstatus_hazardous,
        R.string.airstatus_general_public_guidance_hazardous,
        R.string.airstatus_sensitive_group_guidance_hazardous
    ),

    /** No reading (0, negative, or outside every band). Grey, and no face image. */
    UNKNOWN(AirLevel.UNKNOWN, R.string.airstatus_unknown, null, null)
    ;

    val key: String get() = level.key
    val color: Int get() = level.color
    val foregroundColor: Int get() = level.foregroundColor

    /** Drawable name of the face, `status_good`; there is none for [UNKNOWN]. */
    val imageName: String? get() = if (this == UNKNOWN) null else "status_$key"

    val hasFaceImage: Boolean get() = level.hasFaceImage

    /** A band: `from` inclusive, `until` exclusive. */
    data class Band(val from: Double, val until: Double, val status: AirStatus) {
        operator fun contains(value: Double): Boolean = value >= from && value < until
    }

    companion object {
        /** The six real bands, for legends. Never [UNKNOWN]. */
        val showAllCases: List<AirStatus> = AirLevel.showAllCases.map(::of)

        /** Colour bands for each index, lowest first; the same thresholds as iOS `AirStatuses.bands`. */
        val bands: Map<AirIndexType, List<Band>> = AirLevel.bands.mapValues { (_, levels) ->
            levels.map { Band(it.from, it.until, of(it.level)) }
        }

        fun of(type: AirIndexType, value: Double): AirStatus = of(AirLevel.of(type, value))

        fun of(level: AirLevel): AirStatus = entries.first { it.level == level }
    }
}
