package com.kfpun.twaqi.widget

import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import java.time.Duration
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** FOX-59: when the widgets refresh, and that the refresh respects the network and the battery. */
class WidgetRefreshScheduleTest {
    private val now = Instant.ofEpochSecond(1_793_000_000)

    @Test
    fun refreshesEveryHalfHourWithinATenMinuteWindow() {
        val spec = WidgetRefreshSchedule.periodicRequest().workSpec
        assertEquals(Duration.ofMinutes(30).toMillis(), spec.intervalDuration)
        assertEquals(Duration.ofMinutes(10).toMillis(), spec.flexDuration)
        assertEquals(WidgetRefreshWorker::class.java.name, spec.workerClassName)
    }

    @Test
    fun periodicRefreshNeedsANetworkAndABatteryThatIsNotLow() {
        val constraints = WidgetRefreshSchedule.periodicRequest().workSpec.constraints
        assertEquals(NetworkType.CONNECTED, constraints.requiredNetworkType)
        assertTrue(constraints.requiresBatteryNotLow())
        assertFalse(constraints.requiresCharging())
    }

    @Test
    fun askingAgainKeepsTheRunningSchedule() {
        assertEquals(ExistingPeriodicWorkPolicy.KEEP, WidgetRefreshSchedule.periodicPolicy)
    }

    @Test
    fun refreshRunsOnlyWhileAWidgetIsPlaced() {
        assertFalse(WidgetRefreshSchedule.shouldSchedule(0))
        assertTrue(WidgetRefreshSchedule.shouldSchedule(1))
        assertTrue(WidgetRefreshSchedule.shouldSchedule(3))
    }

    @Test
    fun aNewWidgetFetchesOnceWithANetwork() {
        val spec = WidgetRefreshSchedule.refreshNowRequest().workSpec
        assertEquals(NetworkType.CONNECTED, spec.constraints.requiredNetworkType)
        assertFalse(spec.isPeriodic)
        assertEquals(0L, spec.initialDelay)
    }

    @Test
    fun pageResetRedrawsWithoutTheNetworkWhenTheThirtyMinutesRunOut() {
        val tapped = WidgetPageState(stationId = 2, tappedAt = now.minus(Duration.ofMinutes(5)))
        val resetAt = WidgetPaging.resetAt(tapped, listOf(10, 1, 2), now)
        val delay = WidgetRefreshSchedule.resetDelay(resetAt, now)
        assertEquals(Duration.ofMinutes(25), delay)

        val spec = WidgetRefreshSchedule.resetRequest(delay!!).workSpec
        assertEquals(Duration.ofMinutes(25).toMillis(), spec.initialDelay)
        assertEquals(NetworkType.NOT_REQUIRED, spec.constraints.requiredNetworkType)
        assertTrue(spec.input.getBoolean(WidgetRefreshSchedule.KEY_REDRAW_ONLY, false))
    }

    @Test
    fun noResetOnTheDefaultPageAndNeverInThePast() {
        assertNull(WidgetRefreshSchedule.resetDelay(null, now))
        assertEquals(Duration.ZERO, WidgetRefreshSchedule.resetDelay(now.minusSeconds(5), now))
    }

    @Test
    fun eachWidgetHasItsOwnReset() {
        assertTrue(WidgetRefreshSchedule.resetWorkName(4) != WidgetRefreshSchedule.resetWorkName(5))
    }
}
