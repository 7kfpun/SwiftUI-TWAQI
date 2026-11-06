package com.kfpun.twaqi.data.model

/**
 * The health level of a reading and its colours (iOS `AirStatuses`), without any text: the
 * phone's `AirStatus` adds its labels and guidance, the watch adds
 * its own. Shared by both apps so a level is the same colour on the phone and on the watch.
 * Colours are `0xRRGGBB`.
 */
enum class AirLevel(val key: String, val color: Int, val foregroundColor: Int) {
    GOOD("good", 0x009866, WHITE),
    MODERATE("moderate", 0xFEDE33, BLACK),
    UNHEALTHY_FOR_SENSITIVE_GROUP("unhealthyforsensitivegroup", 0xFE9833, BLACK),
    UNHEALTHY("unhealthy", 0xCC0033, WHITE),
    VERY_UNHEALTHY("veryunhealthy", 0x660098, WHITE),
    HAZARDOUS("hazardous", 0x7E2200, WHITE),

    /** No reading (0, negative, or outside every band). Grey, and no face image. */
    UNKNOWN("unknown", 0x676767, WHITE)
    ;

    val hasFaceImage: Boolean get() = this != UNKNOWN

    /** A band: `from` inclusive, `until` exclusive. */
    data class Band(val from: Double, val until: Double, val level: AirLevel) {
        operator fun contains(value: Double): Boolean = value >= from && value < until
    }

    companion object {
        /** The six real levels, lowest first. Never [UNKNOWN]. */
        val showAllCases: List<AirLevel> =
            listOf(GOOD, MODERATE, UNHEALTHY_FOR_SENSITIVE_GROUP, UNHEALTHY, VERY_UNHEALTHY, HAZARDOUS)

        /** Bands for each index, lowest first; the same thresholds as iOS `AirStatuses.bands`. */
        val bands: Map<AirIndexType, List<Band>> = mapOf(
            AirIndexType.AQI to bands(1.0, 51.0, 101.0, 151.0, 201.0, 301.0, 1000.0),
            AirIndexType.PM25 to bands(0.1, 15.5, 35.5, 54.5, 150.5, 250.5, 5005.0),
            AirIndexType.PM10 to bands(1.0, 55.0, 126.0, 255.0, 355.0, 425.0, 6050.0),
            AirIndexType.O3 to bands(1.0, 55.0, 125.0, 165.0, 205.0, 405.0, 605.0),
            AirIndexType.CO to bands(0.1, 4.5, 9.5, 12.5, 15.5, 30.5, 50.5),
            AirIndexType.SO2 to bands(1.0, 36.0, 76.0, 186.0, 305.0, 605.0, 1005.0),
            AirIndexType.NO2 to bands(1.0, 54.0, 101.0, 361.0, 650.0, 1250.0, 2050.0)
        )

        fun of(type: AirIndexType, value: Double): AirLevel = bands[type]?.firstOrNull { value in it }?.level ?: UNKNOWN

        private fun bands(vararg edges: Double): List<Band> =
            showAllCases.mapIndexed { index, level -> Band(edges[index], edges[index + 1], level) }
    }
}

private const val WHITE = 0xFFFFFF
private const val BLACK = 0x000000
