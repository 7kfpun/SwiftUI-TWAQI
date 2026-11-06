package com.kfpun.twaqi.watch.data

import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirLevel
import com.kfpun.twaqi.watch.MapKeyValueStore
import com.kfpun.twaqi.watch.publishTime
import com.kfpun.twaqi.watch.taipei
import java.time.Duration
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * iOS `WidgetRelevanceTests` (FOX-75): the relevance score on the shared 0–100 scale. The Smart
 * Stack windows (`SmartStackWindows`) have no Wear OS counterpart and are not ported.
 */
class WidgetRelevanceTest {
    /** 2026-11-04 10:20 in Taiwan. */
    private val now = taipei(2026, 11, 4, 10, 20)

    private fun reading(
        stationId: Int = 1,
        aqi: Double,
        pm25: Double = 10.0,
        published: String? = null,
        minutesAgo: Long = 20
    ) = com.kfpun.twaqi.watch.reading(
        stationId = stationId,
        aqi = aqi,
        pm25 = pm25,
        publishTime = published ?: publishTime(now.minus(Duration.ofMinutes(minutesAgo)))
    )

    private fun score(
        reading: WatchReading?,
        type: AirIndexType = AirIndexType.AQI,
        previous: WatchReading? = null,
        threshold: Int? = null,
        isLocked: Boolean = false
    ) = WidgetRelevance.score(reading, type, previous, threshold, isLocked, now)

    // Levels

    @Test
    fun eachLevelScoresHigherThanTheOneBelow() {
        listOf(
            30.0 to 10f,
            80.0 to 25f,
            120.0 to 50f,
            170.0 to 70f,
            250.0 to 85f,
            350.0 to 90f
        ).forEach { (aqi, expected) ->
            assertEquals("AQI $aqi", expected, score(reading(aqi = aqi)))
        }
        val levels = AirLevel.showAllCases.map(WidgetRelevance::levelScore)
        assertEquals(levels.sorted(), levels)
        assertEquals(levels.size, levels.toSet().size)
    }

    @Test
    fun goodStaysLowAndSensitiveGroupsAndAboveScoreHigh() {
        assertTrue(score(reading(aqi = 30.0)) <= 10f)
        assertTrue(score(reading(aqi = 101.0)) >= 50f)
    }

    @Test
    fun noReadingOrNoLevelScoresZero() {
        assertEquals(0f, score(null))
        assertEquals(0f, score(reading(aqi = 0.0)))
    }

    @Test
    fun usesTheLevelOfTheIndexShown() {
        // Good AQI, but PM2.5 unhealthy.
        val mixed = reading(aqi = 40.0, pm25 = 60.0)
        assertEquals(10f, score(mixed, AirIndexType.AQI))
        assertEquals(70f, score(mixed, AirIndexType.PM25))
    }

    @Test
    fun sameLevelScoresTheSameOnEveryIndex() {
        assertEquals(
            score(reading(aqi = 170.0, pm25 = 5.0), AirIndexType.AQI),
            score(reading(aqi = 30.0, pm25 = 60.0), AirIndexType.PM25)
        )
        AirLevel.showAllCases.forEach { assertTrue(WidgetRelevance.levelScore(it) <= WidgetRelevance.MAX_SCORE) }
    }

    // Worsening

    @Test
    fun worseningAddsToTheScore() {
        assertEquals(55f, score(reading(aqi = 130.0), previous = reading(aqi = 110.0, minutesAgo = 80)))
    }

    @Test
    fun improvingOrSteadyAddsNothing() {
        assertEquals(50f, score(reading(aqi = 110.0), previous = reading(aqi = 130.0, minutesAgo = 80)))
        assertEquals(50f, score(reading(aqi = 110.0), previous = reading(aqi = 110.0, minutesAgo = 80)))
    }

    @Test
    fun worseningNeverOutranksTheNextLevel() {
        val worseGood = score(reading(aqi = 50.0), previous = reading(aqi = 20.0, minutesAgo = 80))
        assertTrue(worseGood < score(reading(aqi = 51.0)))
        val worseHazardous = score(reading(aqi = 400.0), previous = reading(aqi = 350.0, minutesAgo = 80))
        assertTrue(worseHazardous <= WidgetRelevance.MAX_SCORE)
    }

    @Test
    fun anotherStationsReadingIsNotAPreviousOne() {
        assertEquals(50f, score(reading(aqi = 130.0), previous = reading(stationId = 2, aqi = 20.0, minutesAgo = 80)))
    }

    // Stale data

    @Test
    fun staleDataScoresZero() {
        val old = reading(aqi = 250.0, minutesAgo = 3 * 60 + 1)
        assertEquals(0f, score(old))
        assertEquals(0f, score(old, threshold = 100))
    }

    @Test
    fun dataJustInsideTheLimitStillScores() {
        assertEquals(85f, score(reading(aqi = 250.0, minutesAgo = 3 * 60)))
    }

    @Test
    fun unreadablePublishTimeScoresZero() {
        assertEquals(0f, score(reading(aqi = 250.0, published = "")))
        assertEquals(0f, score(WatchReading.placeholder))
    }

    // Alert threshold

    @Test
    fun atOrOverTheAlertThresholdScoresTheMaximum() {
        assertEquals(WidgetRelevance.MAX_SCORE, score(reading(aqi = 120.0), threshold = 120))
        assertEquals(WidgetRelevance.MAX_SCORE, score(reading(aqi = 160.0), threshold = 120))
    }

    @Test
    fun underTheAlertThresholdScoresByLevel() {
        assertEquals(50f, score(reading(aqi = 119.0), threshold = 120))
    }

    @Test
    fun thresholdIsOnTheAqiWhateverIndexIsShown() {
        assertEquals(
            WidgetRelevance.MAX_SCORE,
            score(reading(aqi = 130.0, pm25 = 10.0), AirIndexType.PM25, threshold = 120)
        )
        assertEquals(70f, score(reading(aqi = 60.0, pm25 = 60.0), AirIndexType.PM25, threshold = 120))
    }

    @Test
    fun thresholdOutranksEveryLevel() {
        val hazardousWorsening = score(reading(aqi = 400.0), previous = reading(aqi = 350.0, minutesAgo = 80))
        assertTrue(hazardousWorsening < score(reading(aqi = 60.0), threshold = 50))
    }

    @Test
    fun lockedScoresZero() {
        assertEquals(0f, score(reading(aqi = 250.0), threshold = 100, isLocked = true))
    }

    // Previous publish

    @Test
    fun historyKeepsTheLatestTwoPublishesOfAStation() {
        val nine = reading(aqi = 50.0, minutesAgo = 80)
        val ten = reading(aqi = 70.0, minutesAgo = 20)
        var history = WidgetRelevance.recording(nine, emptyList())
        history = WidgetRelevance.recording(ten, history)
        assertEquals(nine, WidgetRelevance.previous(ten, history))

        val eleven = reading(aqi = 90.0, published = publishTime(now.plus(Duration.ofMinutes(40))))
        history = WidgetRelevance.recording(eleven, history)
        assertEquals(listOf(ten, eleven), history.filter { it.stationId == 1 })
        assertEquals(ten, WidgetRelevance.previous(eleven, history))
    }

    /** Two updates inside one hour see the same publish: the one before it stays the previous one. */
    @Test
    fun recordingTheSamePublishAgainKeepsThePreviousOne() {
        val nine = reading(aqi = 50.0, minutesAgo = 80)
        val ten = reading(aqi = 70.0, minutesAgo = 20)
        var history = WidgetRelevance.recording(ten, WidgetRelevance.recording(nine, emptyList()))
        history = WidgetRelevance.recording(ten, history)
        assertEquals(listOf(nine, ten), history)
        assertEquals(nine, WidgetRelevance.previous(ten, history))
    }

    @Test
    fun anOlderReadingDoesNotReplaceANewerOne() {
        val nine = reading(aqi = 50.0, minutesAgo = 80)
        val ten = reading(aqi = 70.0, minutesAgo = 20)
        val history = WidgetRelevance.recording(ten, emptyList())
        assertEquals(history, WidgetRelevance.recording(nine, history))
    }

    @Test
    fun stationsAreKeptApartAndTheHistoryIsBounded() {
        val one = reading(stationId = 1, aqi = 50.0)
        val two = reading(stationId = 2, aqi = 60.0)
        assertNull(
            WidgetRelevance.previous(two, WidgetRelevance.recording(two, WidgetRelevance.recording(one, emptyList())))
        )

        var many = emptyList<WatchReading>()
        for (id in 1..(WidgetRelevance.HISTORY_LIMIT + 5)) {
            many =
                WidgetRelevance.recording(reading(stationId = id, aqi = 50.0), many)
        }
        assertEquals(WidgetRelevance.HISTORY_LIMIT, many.size)
        assertEquals(WidgetRelevance.HISTORY_LIMIT + 5, many.last().stationId)
    }

    // Stored on the watch

    /** Against the real clock: the store leaves out readings a week old. */
    @Test
    fun recordForRelevanceReturnsTheEarlierPublish() {
        val store = WatchStore(MapKeyValueStore())
        val earlier = reading(aqi = 50.0, published = publishTime(Instant.now().minus(Duration.ofMinutes(80))))
        val later = reading(aqi = 70.0, published = publishTime(Instant.now().minus(Duration.ofMinutes(20))))
        assertNull(store.recordForRelevance(earlier))
        assertEquals(earlier, store.recordForRelevance(later))
        // The next update in the same hour still sees the earlier publish.
        assertEquals(earlier, store.recordForRelevance(later))
        assertEquals(listOf(earlier, later), store.relevanceHistory)
    }
}
