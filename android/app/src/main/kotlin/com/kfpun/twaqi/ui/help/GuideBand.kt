package com.kfpun.twaqi.ui.help

import androidx.annotation.StringRes
import com.kfpun.twaqi.R

/**
 * The air-quality levels as the index guide lists them, with the colours and health advice of
 * iOS `AirStatuses`. The guide keeps its own copy until the data layer's `AirStatus` (FOX-53)
 * is on the integration branch; then it should use that one.
 */
enum class GuideStatus(
    val color: Long,
    @param:StringRes val label: Int,
    @param:StringRes val generalPublicGuidance: Int
) {
    GOOD(0xFF009866, R.string.airstatus_good, R.string.airstatus_general_public_guidance_good),
    MODERATE(0xFFFEDE33, R.string.airstatus_moderate, R.string.airstatus_general_public_guidance_moderate),
    UNHEALTHY_FOR_SENSITIVE_GROUP(
        0xFFFE9833,
        R.string.airstatus_unhealthyforsensitivegroup,
        R.string.airstatus_general_public_guidance_unhealthyforsensitivegroup
    ),
    UNHEALTHY(0xFFCC0033, R.string.airstatus_unhealthy, R.string.airstatus_general_public_guidance_unhealthy),
    VERY_UNHEALTHY(
        0xFF660098,
        R.string.airstatus_veryunhealthy,
        R.string.airstatus_general_public_guidance_veryunhealthy
    ),
    HAZARDOUS(0xFF7E2200, R.string.airstatus_hazardous, R.string.airstatus_general_public_guidance_hazardous)
}

/** A band: [from] inclusive, [until] exclusive, the same thresholds as iOS `AirStatuses.bands`. */
data class GuideBand(val from: Double, val until: Double, val status: GuideStatus) {
    companion object {
        fun forPage(page: DefinitionPage): List<GuideBand> = when (page) {
            DefinitionPage.AQI -> bands(1.0, 51.0, 101.0, 151.0, 201.0, 301.0, 1000.0)
            DefinitionPage.PM25 -> bands(0.1, 15.5, 35.5, 54.5, 150.5, 250.5, 5005.0)
            DefinitionPage.PM10 -> bands(1.0, 55.0, 126.0, 255.0, 355.0, 425.0, 6050.0)
            DefinitionPage.O3 -> bands(1.0, 55.0, 125.0, 165.0, 205.0, 405.0, 605.0)
            DefinitionPage.CO -> bands(0.1, 4.5, 9.5, 12.5, 15.5, 30.5, 50.5)
            DefinitionPage.SO2 -> bands(1.0, 36.0, 76.0, 186.0, 305.0, 605.0, 1005.0)
            DefinitionPage.NO2 -> bands(1.0, 54.0, 101.0, 361.0, 650.0, 1250.0, 2050.0)
        }

        private fun bands(vararg edges: Double): List<GuideBand> =
            GuideStatus.entries.mapIndexed { index, status -> GuideBand(edges[index], edges[index + 1], status) }
    }
}
