package com.kfpun.twaqi.shortcuts

import android.content.Context
import androidx.annotation.PluralsRes
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.locale.AppLocale
import java.time.Duration
import java.time.Instant
import java.util.Locale

/**
 * The station a "What's the air?" question or the Quick Settings tile is answered for (FOX-95,
 * iOS `StationPlan`). Pure, so the choice is tested apart from location and the network.
 */
sealed interface StationPlan {
    /** A station by id: the one asked for, or the first favourite standing in for "nearest". */
    data class Station(val stationId: Int) : StationPlan

    /** The station nearest the reader. */
    data object Nearest : StationPlan

    /** The station nearest the 中正 default: no location and no favourite to fall back to. */
    data object DefaultLocation : StationPlan
}

/** Said before the reading when "nearest" was asked for and something else is answered (iOS `StationFallbackNote`). */
enum class StationFallbackNote { FIRST_FAVOURITE, DEFAULT_LOCATION }

/** iOS `StationResolution`. */
data class StationResolution(val plan: StationPlan, val note: StationFallbackNote?) {
    companion object {
        /**
         * [requestedStationId] null means "nearest". Location is used only when the app already
         * has it ([locationAvailable]); it is never asked for here. Without it, the first
         * favourite in the reader's order answers, and without one, the 中正 default.
         */
        fun resolve(requestedStationId: Int?, favouriteIds: List<Int>, locationAvailable: Boolean): StationResolution =
            when {
                requestedStationId != null -> StationResolution(StationPlan.Station(requestedStationId), null)

                locationAvailable -> StationResolution(StationPlan.Nearest, null)

                favouriteIds.isNotEmpty() ->
                    StationResolution(StationPlan.Station(favouriteIds.first()), StationFallbackNote.FIRST_FAVOURITE)

                else -> StationResolution(StationPlan.DefaultLocation, StationFallbackNote.DEFAULT_LOCATION)
            }

        /**
         * The station the Quick Settings tile shows (iOS `controlStationId`, the Control Center
         * control). "Nearest" (null) is [appClosestId], the saved station nearest the reader, when
         * the app may use location; otherwise the first favourite. Null only when there is
         * neither (before the app has ever loaded readings).
         */
        fun controlStationId(
            requestedStationId: Int?,
            appClosestId: Int?,
            favouriteIds: List<Int>,
            locationAllowed: Boolean
        ): Int? {
            val resolution = resolve(requestedStationId, favouriteIds, locationAllowed && appClosestId != null)
            return when (val plan = resolution.plan) {
                is StationPlan.Station -> plan.stationId
                StationPlan.Nearest, StationPlan.DefaultLocation -> appClosestId
            }
        }
    }
}

/** Where an answer's reading came from (iOS `AirQualityAnswer.Freshness`). */
enum class AnswerFreshness {
    /** Fetched just now. */
    LIVE,

    /** The last one saved, because the fetch failed. */
    CACHED
}

/** The units an answer says a reading's age in. */
enum class AgeUnit(@param:PluralsRes val plural: Int) {
    MINUTES(R.plurals.intent_age_minutes),
    HOURS(R.plurals.intent_age_hours),
    DAYS(R.plurals.intent_age_days)
}

/**
 * The sentences of an answer in one language, from `strings.xml` (the iOS `Intent.answer_*`
 * keys). [from] reads them in the app's language; tests build them from the resource files.
 */
class AnswerStrings(
    val chinese: Boolean,
    val fallbackFavourite: String,
    val fallbackDefault: String,
    val noReading: String,
    /** `%s`: the station. */
    val noAqi: String,
    /** `%1$s` station, `%2$s` AQI, `%3$s` level. */
    val reading: String,
    /** `%s`: the pollutant. */
    val mainPollutant: String,
    /** `%s`: what to do. */
    val guidance: String,
    /** `%s`: how long ago. */
    val cachedAge: String,
    val cached: String,
    /** `%s`: how long ago. */
    val oldAge: String,
    val status: (AirStatus) -> String,
    val publicGuidance: (AirStatus) -> String,
    val age: (AgeUnit, Int) -> String
) {
    companion object {
        /** In the app's language (FOX-56), also from a tile or a shortcut with no activity. */
        fun from(context: Context): AnswerStrings {
            val localized = AppLocale.localizedContext(context)
            val res = localized.resources
            return AnswerStrings(
                chinese = AppLocale.isChinese(context),
                fallbackFavourite = res.getString(R.string.intent_answer_fallback_favourite),
                fallbackDefault = res.getString(R.string.intent_answer_fallback_default),
                noReading = res.getString(R.string.intent_answer_no_reading),
                noAqi = res.getString(R.string.intent_answer_no_aqi),
                reading = res.getString(R.string.intent_answer_reading),
                mainPollutant = res.getString(R.string.intent_answer_main_pollutant),
                guidance = res.getString(R.string.intent_answer_guidance),
                cachedAge = res.getString(R.string.intent_answer_cached_age),
                cached = res.getString(R.string.intent_answer_cached),
                oldAge = res.getString(R.string.intent_answer_old_age),
                status = { res.getString(it.label) },
                publicGuidance = { status -> status.generalPublicGuidance?.let(res::getString).orEmpty() },
                age = { unit, count -> res.getQuantityString(unit.plural, count, count) }
            )
        }
    }
}

/** What the answer card says for a reading, in the app's language (iOS `AirQualityAnswer`). */
object AirQualityAnswer {
    /**
     * A live reading published longer ago than this says how old it is too: readings are hourly,
     * so this is a station that has missed a publish.
     */
    val staleAfter: Duration = Duration.ofHours(2)

    fun text(
        reading: Pollutant?,
        freshness: AnswerFreshness,
        note: StationFallbackNote?,
        strings: AnswerStrings,
        now: Instant = Instant.now()
    ): String {
        val sentences = mutableListOf<String>()
        when (note) {
            StationFallbackNote.FIRST_FAVOURITE -> sentences += strings.fallbackFavourite
            StationFallbackNote.DEFAULT_LOCATION -> sentences += strings.fallbackDefault
            null -> Unit
        }

        if (reading == null) {
            sentences += strings.noReading
            return join(sentences, strings.chinese)
        }

        val status = reading.status(AirIndexType.AQI)
        val name = name(reading, strings.chinese)
        if (status == AirStatus.UNKNOWN) {
            sentences += format(strings.noAqi, name)
            return join(sentences, strings.chinese)
        }

        sentences += format(strings.reading, name, AirIndexType.AQI.format(reading.aqi), strings.status(status))
        mainPollutant(reading)?.let { sentences += format(strings.mainPollutant, it.label) }
        sentences += format(strings.guidance, strings.publicGuidance(status))

        val age = age(reading, now)
        if (age != null) {
            val ageText = ageString(age, strings)
            if (freshness == AnswerFreshness.CACHED) {
                sentences += format(strings.cachedAge, ageText)
            } else if (age > staleAfter) {
                sentences += format(strings.oldAge, ageText)
            }
        } else if (freshness == AnswerFreshness.CACHED) {
            sentences += strings.cached
        }
        return join(sentences, strings.chinese)
    }

    /**
     * The pollutant in the worst band, named only when the AQI is past good, as MOENV names a
     * 主要污染物 only above 50. Ties go to the first in PM2.5, PM10, O3, NO2, SO2, CO order. Null
     * when every pollutant is good.
     */
    fun mainPollutant(reading: Pollutant): AirIndexType? {
        val bands = AirStatus.showAllCases
        val aqiBand = bands.indexOf(reading.status(AirIndexType.AQI))
        if (aqiBand <= 0) return null

        var main: AirIndexType? = null
        var mainBand = 0
        for (type in POLLUTANT_ORDER) {
            val band = bands.indexOf(reading.status(type))
            if (band > mainBand) {
                main = type
                mainBand = band
            }
        }
        return main
    }

    /** The station's name in the answer's language, never blank. */
    fun name(reading: Pollutant, chinese: Boolean): String = reading.displayName(chinese)

    /** How long ago [reading] was published; null when its time doesn't parse. */
    fun age(reading: Pollutant, now: Instant): Duration? =
        reading.publishedAt?.let { Duration.between(it, now).coerceAtLeast(Duration.ZERO) }

    /** "3 hours" / "3小時": the largest whole unit, at least a minute. */
    fun ageString(age: Duration, strings: AnswerStrings): String {
        val atLeastAMinute = age.coerceAtLeast(Duration.ofMinutes(1))
        return when {
            atLeastAMinute >= Duration.ofDays(2) -> strings.age(AgeUnit.DAYS, atLeastAMinute.toDays().toInt())
            atLeastAMinute >= Duration.ofHours(1) -> strings.age(AgeUnit.HOURS, atLeastAMinute.toHours().toInt())
            else -> strings.age(AgeUnit.MINUTES, atLeastAMinute.toMinutes().toInt())
        }
    }

    private val POLLUTANT_ORDER = listOf(
        AirIndexType.PM25,
        AirIndexType.PM10,
        AirIndexType.O3,
        AirIndexType.NO2,
        AirIndexType.SO2,
        AirIndexType.CO
    )

    private fun format(template: String, vararg args: Any): String = String.format(Locale.ROOT, template, *args)

    /** Chinese sentences run on; English ones take a space. */
    private fun join(sentences: List<String>, chinese: Boolean): String =
        sentences.joinToString(if (chinese) "" else " ")
}
