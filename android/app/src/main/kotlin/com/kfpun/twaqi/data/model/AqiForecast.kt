package com.kfpun.twaqi.data.model

import java.time.Instant

/**
 * One day of MOENV's forecast for one 空品區 (AQF_P_01), as the Worker mirrors it into Directus
 * `twaqi_aqi_forecast` (iOS `AqiForecast`).
 *
 * [area] is MOENV's short name ("北部", "雲嘉南"), not the station API's "北部空品區";
 * [AqiForecastMatcher] joins the two. [forecastDate] is a Taiwan day, `YYYY-MM-DD`;
 * [publishTime] is Taiwan local time, `"2026-10-31 16:30:00"`.
 */
data class AqiForecast(
    val area: String,
    val forecastDate: String,
    val aqi: Int? = null,
    val majorPollutant: String? = null,
    val minorPollutant: String? = null,
    val minorPollutantAqi: Int? = null,
    val content: String? = null,
    val publishTime: String? = null,
    /** The Worker's translations of [content] by language, plus their source under `"zh-Hant"`. */
    val contentI18n: Map<String, String>? = null
) {
    val status: AirStatus get() = AirStatus.of(AirIndexType.AQI, (aqi ?: 0).toDouble())

    val publishedAt: Instant? get() = publishTime?.let(TaiwanTime::parsePublishTime)

    /** The Worker's translation into [language] ("en"), only when made from this exact text. */
    fun translatedContent(language: String?): String? {
        if (language == null) return null
        val source = content?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        val map = contentI18n ?: return null
        if (map[SOURCE_LANGUAGE]?.trim() != source) return null
        return map[language]?.trim()?.takeIf { it.isNotEmpty() }
    }

    /** MOENV's Chinese name in Chinese, the usual symbol otherwise; null when none is named. */
    fun displayMajorPollutant(chinese: Boolean): String? =
        majorPollutant?.let { AqiForecastPollutant.display(it, chinese) }

    companion object {
        const val SOURCE_LANGUAGE = "zh-Hant"
    }
}

/** A station's 空品區 and its forecast days, today onwards. */
data class AreaForecast(val areaTitle: String, val days: List<AqiForecast>) {
    val publishedAt: Instant? get() = days.mapNotNull { it.publishedAt }.maxOrNull()

    /** MOENV repeats one text on every row of a publish; shown once. */
    val content: String? get() = contentDay?.content?.trim()

    fun translatedContent(language: String?): String? = contentDay?.translatedContent(language)

    private val contentDay: AqiForecast?
        get() = days.sortedByDescending { it.publishTime ?: "" }.firstOrNull { !it.content.isNullOrBlank() }
}

/** Joins a station's 空品區 to MOENV forecast areas (iOS `AqiForecastMatcher`). */
object AqiForecastMatcher {
    /** "北部空品區" → "北部"; folds 臺/台 and whitespace. */
    fun normalize(name: String): String = name
        .replace("臺", "台")
        .replace("空品區", "")
        .replace("空品", "")
        .replace("地區", "")
        .filterNot { it.isWhitespace() }

    /** Island stations may carry a catch-all area label, so their county decides. */
    private val islandAreas = listOf("連江" to "馬祖", "金門" to "金門", "澎湖" to "澎湖")

    fun area(areaLocal: String?, countyLocal: String?, areas: List<String>): String? {
        val byKey = LinkedHashMap<String, String>()
        areas.forEach { byKey.putIfAbsent(normalize(it), it) }

        if (areaLocal != null) {
            val key = normalize(areaLocal)
            if (key.isNotEmpty()) {
                byKey[key]?.let { return it }
                byKey.entries.firstOrNull { key.startsWith(it.key) || it.key.startsWith(key) }?.let { return it.value }
            }
        }

        val county = countyLocal?.let(::normalize)
        if (!county.isNullOrEmpty()) {
            val island = islandAreas.firstOrNull { county.contains(it.first) }
            if (island != null) return byKey[normalize(island.second)]
        }
        return null
    }

    /** Today-onwards days for the station, soonest first, at most [limit]. */
    fun forecast(
        areaLocal: String?,
        countyLocal: String?,
        forecasts: List<AqiForecast>,
        title: String? = null,
        today: String = TaiwanTime.today(),
        limit: Int = 3
    ): AreaForecast? {
        val current = forecasts.filter { it.forecastDate >= today }
        val areas = current.map { it.area }.toSortedSet().toList()
        val area = area(areaLocal, countyLocal, areas) ?: return null
        val days = days(area, current, today).take(limit)
        if (days.isEmpty()) return null
        val areaTitle = title?.takeIf { it.isNotEmpty() } ?: areaLocal?.takeIf { it.isNotEmpty() } ?: "${area}空品區"
        return AreaForecast(areaTitle, days)
    }

    /** Today-onwards days for one MOENV [area], soonest first; the newest publish wins a repeated day. */
    fun days(area: String, forecasts: List<AqiForecast>, today: String): List<AqiForecast> {
        val byDate = HashMap<String, AqiForecast>()
        for (row in forecasts) {
            if (row.area != area || row.forecastDate < today) continue
            val existing = byDate[row.forecastDate]
            if (existing != null && (existing.publishTime ?: "") >= (row.publishTime ?: "")) continue
            byDate[row.forecastDate] = row
        }
        return byDate.values.sortedBy { it.forecastDate }
    }
}

/** MOENV names pollutants in Chinese ("細懸浮微粒", "臭氧8小時"). */
object AqiForecastPollutant {
    /** Most specific first: 細懸浮微粒 contains 懸浮微粒. */
    private val symbols = listOf(
        "細懸浮微粒" to "PM2.5",
        "懸浮微粒" to "PM10",
        "臭氧8小時" to "O₃ (8h)",
        "臭氧八小時" to "O₃ (8h)",
        "臭氧" to "O₃",
        "二氧化氮" to "NO₂",
        "二氧化硫" to "SO₂",
        "一氧化碳" to "CO"
    )

    fun display(raw: String, chinese: Boolean): String? {
        val value = raw.trim()
        if (value.isEmpty() || value == "-") return null
        if (chinese) return value
        return symbols.firstOrNull { value.contains(it.first) }?.second ?: value
    }
}

/** One 空品區 on the Forecast tab (iOS `ForecastTabArea`, FOX-32). */
data class ForecastTabArea(val area: String, val pin: Pin, val forecast: AreaForecast) {
    enum class Pin { READER, FALLBACK, FAVOURITE, NONE }
}

/** Orders every 空品區 for the Forecast tab: the reader's, then favourites', then MOENV order. */
object ForecastTabOrdering {
    const val FALLBACK_AREA = "北部"

    val regionOrder = listOf("北部", "竹苗", "中部", "雲嘉南", "高屏", "宜蘭", "花東", "澎湖", "金門", "馬祖")

    fun areas(
        forecasts: List<AqiForecast>,
        readerArea: String?,
        favouriteAreas: List<String?>,
        today: String,
        chinese: Boolean
    ): List<ForecastTabArea> {
        val available = forecasts.filter { it.forecastDate >= today }.map { it.area }.toSet()
        val seen = HashSet<String>()
        val ordered = ArrayList<Pair<String, ForecastTabArea.Pin>>()
        fun add(area: String, pin: ForecastTabArea.Pin) {
            if (area in available && seen.add(area)) ordered += area to pin
        }

        if (readerArea != null && readerArea in available) {
            add(readerArea, ForecastTabArea.Pin.READER)
        } else {
            add(FALLBACK_AREA, ForecastTabArea.Pin.FALLBACK)
        }
        favouriteAreas.filterNotNull().forEach { add(it, ForecastTabArea.Pin.FAVOURITE) }
        available
            .sortedWith(
                compareBy<String> {
                    regionOrder.indexOf(it).let { i ->
                        if (i <
                            0
                        ) {
                            regionOrder.size
                        } else {
                            i
                        }
                    }
                }.thenBy { it }
            )
            .forEach { add(it, ForecastTabArea.Pin.NONE) }

        return ordered.mapNotNull { (area, pin) ->
            val days = AqiForecastMatcher.days(area, forecasts, today)
            if (days.isEmpty()) null else ForecastTabArea(area, pin, AreaForecast(title(area, chinese), days))
        }
    }

    /** The text every area shares, shown once above the list; null when they differ or fewer than two have one. */
    fun sharedContent(areas: List<ForecastTabArea>): String? {
        val contents = areas.mapNotNull { it.forecast.content }
        return if (contents.size > 1 && contents.toSet().size == 1) contents.first() else null
    }

    fun sharedTranslation(areas: List<ForecastTabArea>, language: String?): String? {
        val shared = sharedContent(areas) ?: return null
        return areas.asSequence()
            .filter { it.forecast.content == shared }
            .mapNotNull { it.forecast.translatedContent(language) }
            .firstOrNull()
    }

    private val englishNames = mapOf(
        "北部" to "North",
        "竹苗" to "Chu-Miao",
        "中部" to "Central",
        "雲嘉南" to "Yun-Chia-Nan",
        "高屏" to "Kao-Ping",
        "宜蘭" to "Yilan",
        "花東" to "Hua-Tung",
        "澎湖" to "Penghu",
        "金門" to "Kinmen",
        "馬祖" to "Matsu"
    )

    private val islands = setOf("澎湖", "金門", "馬祖")

    /** "北部空品區" / "North"; an island is its name alone ("金門" / "Kinmen"). */
    fun title(area: String, chinese: Boolean): String {
        val key = AqiForecastMatcher.normalize(area)
        if (chinese) return if (key in islands) key else "${key}空品區"
        return englishNames[key] ?: area
    }
}
