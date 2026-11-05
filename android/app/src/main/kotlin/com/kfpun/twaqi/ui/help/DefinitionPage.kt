package com.kfpun.twaqi.ui.help

import androidx.annotation.StringRes
import com.kfpun.twaqi.R
import java.net.URLEncoder
import java.util.Locale

/**
 * One index guide page (iOS `DefinitionPages`): what the index means, where it comes from, what
 * to do about it, and the colour bands the app scores it against.
 *
 * @property unit shown after the band ranges, as on iOS (none for the AQI).
 * @property step the smallest change the bands break at: tenths for PM2.5 and CO, else whole numbers.
 */
enum class DefinitionPage(
    val key: String,
    @param:StringRes val title: Int,
    val unit: String,
    val step: Double,
    private val englishArticle: String,
    private val chineseArticle: String
) {
    AQI("aqi", R.string.airindex_meaning_aqi, "", 1.0, "Air_quality_index", "空氣品質指標"),
    PM25("pm25", R.string.airindex_meaning_pm25, "μg/m3", 0.1, "Particulates", "細懸浮微粒"),
    PM10("pm10", R.string.airindex_meaning_pm10, "μg/m3", 1.0, "Particulates", "懸浮粒子"),
    O3("o3", R.string.airindex_meaning_o3, "ppb", 1.0, "Tropospheric_ozone", "臭氧"),
    CO("co", R.string.airindex_meaning_co, "ppm", 0.1, "Carbon_monoxide", "一氧化碳"),
    SO2("so2", R.string.airindex_meaning_so2, "ppb", 1.0, "Sulfur_dioxide", "二氧化硫"),
    NO2("no2", R.string.airindex_meaning_no2, "ppb", 1.0, "Nitrogen_dioxide", "二氧化氮")
    ;

    /** A section: its header and body. */
    data class Section(@param:StringRes val header: Int, @param:StringRes val body: Int)

    /**
     * The page's sections, in reading order. The AQI is a scale rather than a pollutant, so it
     * has no sources or health section of its own: its bands carry the health advice.
     */
    val sections: List<Section>
        get() = when (this) {
            AQI -> listOf(
                Section(R.string.guide_section_what, R.string.guide_aqi_what),
                Section(R.string.guide_section_measure, R.string.guide_aqi_measure),
                Section(R.string.guide_section_tips, R.string.guide_aqi_tips)
            )

            PM25 -> pollutant(
                R.string.guide_pm25_what,
                R.string.guide_pm25_sources,
                R.string.guide_pm25_health,
                R.string.guide_pm25_measure,
                R.string.guide_pm25_tips
            )

            PM10 -> pollutant(
                R.string.guide_pm10_what,
                R.string.guide_pm10_sources,
                R.string.guide_pm10_health,
                R.string.guide_pm10_measure,
                R.string.guide_pm10_tips
            )

            O3 -> pollutant(
                R.string.guide_o3_what,
                R.string.guide_o3_sources,
                R.string.guide_o3_health,
                R.string.guide_o3_measure,
                R.string.guide_o3_tips
            )

            CO -> pollutant(
                R.string.guide_co_what,
                R.string.guide_co_sources,
                R.string.guide_co_health,
                R.string.guide_co_measure,
                R.string.guide_co_tips
            )

            SO2 -> pollutant(
                R.string.guide_so2_what,
                R.string.guide_so2_sources,
                R.string.guide_so2_health,
                R.string.guide_so2_measure,
                R.string.guide_so2_tips
            )

            NO2 -> pollutant(
                R.string.guide_no2_what,
                R.string.guide_no2_sources,
                R.string.guide_no2_health,
                R.string.guide_no2_measure,
                R.string.guide_no2_tips
            )
        }

    /** The colour bands for this index, lowest first. */
    val bands: List<GuideBand> get() = GuideBand.forPage(this)

    /** Wikipedia in the reader's language, for anyone who wants more depth. */
    fun url(chinese: Boolean): String {
        val host = if (chinese) "zh.wikipedia.org" else "en.wikipedia.org"
        val article = if (chinese) chineseArticle else englishArticle
        return "https://$host/wiki/" + URLEncoder.encode(article, "UTF-8").replace("+", "%20")
    }

    /**
     * "15.5–35.4 μg/m3": bounds as a reader would say them, not the half-open ranges in code.
     * The first band starts at zero; the last is open-ended.
     */
    fun rangeText(band: GuideBand, isLast: Boolean): String {
        val decimals = if (step < 1) 1 else 0
        val unitText = if (unit.isEmpty()) "" else " $unit"
        val lower = if (band.from <= step) 0.0 else band.from
        val lowerText = format(lower, decimals)
        if (isLast) return "$lowerText+$unitText"
        return "$lowerText–${format(band.until - step, decimals)}$unitText"
    }

    companion object {
        fun fromKey(key: String): DefinitionPage? = entries.firstOrNull { it.key == key }

        private fun pollutant(what: Int, sources: Int, health: Int, measure: Int, tips: Int) = listOf(
            Section(R.string.guide_section_what, what),
            Section(R.string.guide_section_sources, sources),
            Section(R.string.guide_section_health, health),
            Section(R.string.guide_section_measure, measure),
            Section(R.string.guide_section_tips, tips)
        )

        private fun format(value: Double, decimals: Int): String = String.format(Locale.US, "%.${decimals}f", value)
    }
}
