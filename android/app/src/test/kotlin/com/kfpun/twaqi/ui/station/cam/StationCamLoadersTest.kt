package com.kfpun.twaqi.ui.station.cam

import com.kfpun.twaqi.data.Fixtures
import com.kfpun.twaqi.data.cams.CamFrame
import com.kfpun.twaqi.data.cams.CamFrameSource
import com.kfpun.twaqi.data.cams.CamHistorySource
import com.kfpun.twaqi.data.cams.CamHourResult
import com.kfpun.twaqi.data.cams.StationCam
import com.kfpun.twaqi.data.cams.StationCamHour
import com.kfpun.twaqi.data.cams.StationCamManifest
import com.kfpun.twaqi.data.cams.StationCamState
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** iOS `StationCamFrameLoader` and `StationCamHistoryLoader`: what the frame shows as the scrubber moves. */
@OptIn(ExperimentalCoroutinesApi::class)
class StationCamLoadersTest {
    private val anchor = Instant.parse("2026-10-30T14:30:00Z") // 22:30 in Taiwan
    private var now = anchor

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private class FakeHistory : CamHistorySource<String> {
        val onDisk = mutableMapOf<String, String>()
        val remote = mutableMapOf<String, CamHourResult<String>>()
        val loads = mutableListOf<String>()

        override suspend fun savedThumbnail(hour: StationCamHour) = onDisk[hour.key]?.let { "thumb:$it" }

        override suspend fun savedFullImage(hour: StationCamHour) = onDisk[hour.key]?.let { "full:$it" }

        override suspend fun load(hour: StationCamHour): CamHourResult<String> {
            loads += hour.key
            savedThumbnail(hour)?.let { return CamHourResult.Thumbnail(it) }
            val result = remote[hour.key] ?: CamHourResult.Failed
            if (result is CamHourResult.Thumbnail) onDisk[hour.key] = result.image
            return (result as? CamHourResult.Thumbnail)?.let { CamHourResult.Thumbnail("thumb:${it.image}") } ?: result
        }
    }

    private fun TestScope.historyLoader(source: FakeHistory) =
        StationCamHistoryLoader(source, backgroundScope) { now }.apply { configure("001", anchor) }

    @Test
    fun configureOffersTheTwentyFourHoursUpToTheAnchor() = runTest(UnconfinedTestDispatcher()) {
        val loader = historyLoader(FakeHistory())
        val slots = loader.state.value.slots
        assertEquals(24, slots.size)
        assertEquals("2026-10-30/22", slots.last().key)
        assertEquals("2026-10-29/23", slots.first().key)
        assertNull(loader.state.value.selected)
    }

    /** A 404 shows "no image for this hour", not "couldn't load", and the neighbours still load. */
    @Test
    fun aMissingHourIsShownAsMissingNotAsAnError() = runTest(UnconfinedTestDispatcher()) {
        val source = FakeHistory()
        val loader = historyLoader(source)
        val slots = loader.state.value.slots
        source.remote[slots[10].key] = CamHourResult.Missing
        source.remote[slots[9].key] = CamHourResult.Thumbnail("09")
        source.remote[slots[11].key] = CamHourResult.Thumbnail("11")

        loader.preview(10, standIn = "live")
        loader.settle(10)

        val state = loader.state.value
        assertEquals(slots[10], state.selected)
        assertEquals(CamSlotState.MISSING, state.selectedState)
        assertEquals(CamSlotState.LOADED, state.states[slots[9]])
        assertEquals(CamSlotState.LOADED, state.states[slots[11]])
        assertEquals(CamSlotState.FAILED, state.states[slots[8]])
        // Only the slot and two either side were asked for, nearest first.
        assertEquals(listOf(10, 9, 11, 8, 12).map { slots[it].key }, source.loads)
    }

    @Test
    fun aMissingHourIsAskedForAgainOnlyAfterFiveMinutes() = runTest(UnconfinedTestDispatcher()) {
        val source = FakeHistory()
        val loader = historyLoader(source)
        val hour = loader.state.value.slots[23]
        source.remote[hour.key] = CamHourResult.Missing

        loader.settle(23)
        loader.settle(23)
        assertEquals(1, source.loads.count { it == hour.key })

        now = now.plus(StationCamHistoryLoader.MISSING_RETRY)
        source.remote[hour.key] = CamHourResult.Thumbnail("23")
        loader.settle(23)
        assertEquals(2, source.loads.count { it == hour.key })
        assertEquals(CamSlotState.LOADED, loader.state.value.selectedState)
        assertEquals("full:23", loader.state.value.image)
    }

    /** While scrubbing, the live frame stays up dimmed until the hour is in; then its full frame replaces the thumbnail. */
    @Test
    fun theLiveFrameStandsInUntilTheHourLoads() = runTest(UnconfinedTestDispatcher()) {
        val source = FakeHistory()
        val loader = historyLoader(source)
        source.remote[loader.state.value.slots[5].key] = CamHourResult.Thumbnail("05")

        loader.preview(5, standIn = "live")
        assertEquals("live", loader.state.value.image)
        assertTrue(loader.state.value.isStandIn)
        // Scrubbing never touches the network.
        assertTrue(source.loads.isEmpty())

        loader.settle(5)
        assertEquals("full:05", loader.state.value.image)
        assertFalse(loader.state.value.isStandIn)
    }

    @Test
    fun scrubbingShowsASavedHourFromDisk() = runTest(UnconfinedTestDispatcher()) {
        val source = FakeHistory()
        val loader = historyLoader(source)
        source.onDisk[loader.state.value.slots[3].key] = "03"

        loader.preview(3, standIn = "live")
        assertEquals("thumb:03", loader.state.value.image)
        assertFalse(loader.state.value.isStandIn)
        assertTrue(source.loads.isEmpty())
    }

    @Test
    fun liveClearsTheSelection() = runTest(UnconfinedTestDispatcher()) {
        val loader = historyLoader(FakeHistory())
        loader.settle(4)
        loader.showLive()
        assertNull(loader.state.value.selected)
    }

    /** A new anchor slides the window: hours still in it keep what they loaded. */
    @Test
    fun aNewAnchorKeepsTheHoursStillOnOffer() = runTest(UnconfinedTestDispatcher()) {
        val source = FakeHistory()
        val loader = historyLoader(source)
        val hour = loader.state.value.slots[23]
        source.remote[hour.key] = CamHourResult.Missing
        loader.settle(23)

        loader.configure("001", anchor.plus(Duration.ofHours(1)))
        val state = loader.state.value
        assertEquals(hour, state.slots[22])
        assertEquals(CamSlotState.MISSING, state.states[hour])

        loader.configure("057", anchor)
        assertTrue(loader.state.value.states.isEmpty())
        assertNull(loader.state.value.selected)
    }

    // The live frame

    private val cam = StationCam("001", "基隆", 25.129167, 121.760056, "2026-10-30T22:30:00+08:00")

    private class FakeFrames(var saved: CamFrame<String>?, var fresh: CamFrame<String>?) : CamFrameSource<String> {
        var fetches = 0

        override suspend fun savedFrame(siteId: String) = saved

        override suspend fun fetch(cam: StationCam): CamFrame<String>? {
            fetches += 1
            return fresh
        }
    }

    @Test
    fun theSavedFrameShowsThenTheFreshOneReplacesIt() = runTest(UnconfinedTestDispatcher()) {
        val source = FakeFrames(saved = CamFrame("old", "2026-10-30T21:30:00+08:00"), fresh = CamFrame("new", cam.time))
        val loader = StationCamFrameLoader(source, backgroundScope)

        loader.load(cam)
        assertEquals(CamFrameState("new", cam.time, isRefreshing = false, refreshFailed = false), loader.state.value)
        assertEquals(1, source.fetches)
    }

    @Test
    fun aSavedFrameThatIsTheManifestsLatestIsNotFetchedAgain() = runTest(UnconfinedTestDispatcher()) {
        val source = FakeFrames(saved = CamFrame("saved", cam.time), fresh = null)
        val loader = StationCamFrameLoader(source, backgroundScope)

        loader.load(cam)
        assertEquals("saved", loader.state.value.image)
        assertEquals(0, source.fetches)
    }

    /** Offline: the last saved frame stays up, flagged as such, and the next appearance tries again. */
    @Test
    fun aFailedRefreshKeepsTheSavedFrameAndRetriesNextTime() = runTest(UnconfinedTestDispatcher()) {
        val source = FakeFrames(saved = CamFrame("old", "2026-10-30T21:30:00+08:00"), fresh = null)
        val loader = StationCamFrameLoader(source, backgroundScope)

        loader.load(cam)
        assertEquals("old", loader.state.value.image)
        assertEquals("2026-10-30T21:30:00+08:00", loader.state.value.imageTime)
        assertTrue(loader.state.value.refreshFailed)

        source.fresh = CamFrame("new", cam.time)
        loader.load(cam)
        assertEquals("new", loader.state.value.image)
        assertEquals(2, source.fetches)

        // Loaded fine: the same cam on the next appearance isn't fetched again.
        loader.load(cam)
        assertEquals(2, source.fetches)
    }

    // Which cam the station has

    private val cams = requireNotNull(StationCamManifest.parse(Fixtures.stationCamsManifest))

    private fun model() = StationCamViewModel({ cams }, FakeFrames(null, null), FakeHistory())

    @Test
    fun theFirstCopyOfTheStationToMatchWins() {
        val model = model()
        model.findCam("Keelung", 0.0, 0.0)
        assertEquals(StationCamState.Missing, model.cam.value)

        // The station record's Chinese name still finds it.
        model.findCam("基隆", 25.129167, 121.760056)
        assertEquals("001", (model.cam.value as StationCamState.Available).cam.siteId)

        model.findCam("前鎮", 0.0, 0.0)
        assertEquals("001", (model.cam.value as StationCamState.Available).cam.siteId)
    }
}
