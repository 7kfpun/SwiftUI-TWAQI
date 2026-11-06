package com.kfpun.twaqi.onboarding

import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.onboarding.OnboardingTest.Companion.station
import com.kfpun.twaqi.ui.main.GeoPoint
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** iOS `OnboardingViewModel`: where each answer takes the flow, and the events it logs. */
@OptIn(ExperimentalCoroutinesApi::class)
class OnboardingViewModelTest {
    private lateinit var dispatcher: TestDispatcher
    private val events = mutableListOf<Pair<String, Map<String, Any>>>()

    private val kaohsiung = station(1, 22.6273, 120.3014)
    private val zhongzheng = station(2, 25.0330, 121.5150)

    @Before
    fun setUp() {
        dispatcher = StandardTestDispatcher()
        Dispatchers.setMain(dispatcher)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        Onboarding.resetForTests()
    }

    private fun model(
        location: PermissionState = PermissionState.NOT_ASKED,
        notifications: PermissionState = PermissionState.NOT_ASKED,
        stations: List<Pollutant> = listOf(kaohsiung, zhongzheng),
        fix: GeoPoint? = null,
        locate: suspend () -> GeoPoint? = { fix }
    ) = OnboardingViewModel(location, notifications, { stations }, locate) { name, parameters ->
        events += name to parameters
    }

    private val step get() = events.filter { it.first == Analytics.ONBOARDING_STEP_VIEWED }.map { it.second["step"] }

    private fun OnboardingViewModel.walkTo(target: OnboardingStep) {
        while (uiState.value.step != target) goForward()
    }

    // Back and forward

    @Test
    fun opensOnWelcomeAndLogsIt() {
        val vm = model()
        assertEquals(OnboardingStep.WELCOME, vm.uiState.value.step)
        assertEquals(Analytics.ONBOARDING_STEP_VIEWED to mapOf("step" to "welcome", "index" to 1), events.single())
    }

    @Test
    fun forwardWalksTheStepsAndStopsAtTheLast() {
        val vm = model()
        repeat(10) { vm.goForward() }
        assertEquals(OnboardingStep.MORE, vm.uiState.value.step)
        // Each step logged once, in order.
        assertEquals(listOf("welcome", "location", "closest_station", "notifications", "more"), step)
    }

    @Test
    fun backReturnsAStepAndStopsAtTheFirst() {
        val vm = model()
        vm.walkTo(OnboardingStep.CLOSEST_STATION)
        vm.goBack()
        assertEquals(OnboardingStep.LOCATION, vm.uiState.value.step)
        vm.goBack()
        vm.goBack()
        assertEquals(OnboardingStep.WELCOME, vm.uiState.value.step)
        assertEquals(listOf("welcome", "location", "closest_station", "location", "welcome"), step)
    }

    // Skip and done

    @Test
    fun skipLogsTheStepItEndedOn() {
        val vm = model()
        vm.walkTo(OnboardingStep.NOTIFICATIONS)
        vm.finish(skippedAt = OnboardingStep.NOTIFICATIONS, isLaunchFlow = false)

        assertEquals(Analytics.ONBOARDING_SKIPPED to mapOf("label" to "step_4"), events.last())
        assertFalse(events.any { it.first == Analytics.ONBOARDING_COMPLETED })
    }

    @Test
    fun doneLogsCompletedOnce() {
        val vm = model()
        vm.walkTo(OnboardingStep.MORE)
        vm.finish(isLaunchFlow = false)
        vm.finish(isLaunchFlow = false)

        assertEquals(1, events.count { it.first == Analytics.ONBOARDING_COMPLETED })
    }

    @Test
    fun finishingTheLaunchRunReleasesTheHoldAndAHelpRunDoesNot() {
        Onboarding.decideLaunch(showsOnLaunch = true)
        model().finish(skippedAt = OnboardingStep.WELCOME, isLaunchFlow = false)
        assertTrue(Onboarding.isOpenAtLaunch.value)

        model().finish(skippedAt = OnboardingStep.WELCOME, isLaunchFlow = true)
        assertFalse(Onboarding.isOpenAtLaunch.value)
    }

    @Test
    fun nothingMovesTheStepAfterSkip() = runTest(dispatcher) {
        val vm = model(fix = GeoPoint(25.0, 121.5))
        vm.walkTo(OnboardingStep.LOCATION)
        vm.locationAsked()
        vm.locationAnswered(granted = true, prompted = true)
        runCurrent()
        vm.finish(skippedAt = OnboardingStep.LOCATION, isLaunchFlow = false)
        advanceTimeBy(OnboardingViewModel.SUCCESS_PAUSE_MILLIS + 100)
        runCurrent()

        assertEquals(OnboardingStep.LOCATION, vm.uiState.value.step)
    }

    // Location (step 2)

    @Test
    fun grantingLocationShowsSuccessThenMovesOn() = runTest(dispatcher) {
        val vm = model(fix = GeoPoint(22.63, 120.30))
        vm.walkTo(OnboardingStep.LOCATION)
        vm.locationAsked()
        assertEquals(PermissionState.ASKING, vm.uiState.value.location)

        vm.locationAnswered(granted = true, prompted = true)
        runCurrent()
        assertEquals(PermissionState.ON, vm.uiState.value.location)
        assertEquals(OnboardingStep.LOCATION, vm.uiState.value.step)
        assertTrue(events.contains(Analytics.ONBOARDING_LOCATION to mapOf("label" to "on")))

        advanceTimeBy(OnboardingViewModel.SUCCESS_PAUSE_MILLIS + 1)
        runCurrent()
        assertEquals(OnboardingStep.CLOSEST_STATION, vm.uiState.value.step)
    }

    @Test
    fun aFixThatNeverComesHoldsNothing() = runTest(dispatcher) {
        val vm = model(locate = { awaitCancellation() })
        vm.walkTo(OnboardingStep.LOCATION)
        vm.locationAsked()
        vm.locationAnswered(granted = true, prompted = true)
        // On at once, not when the fix comes.
        assertEquals(PermissionState.ON, vm.uiState.value.location)
        advanceTimeBy(OnboardingViewModel.SUCCESS_PAUSE_MILLIS + 1)
        runCurrent()
        assertEquals(OnboardingStep.CLOSEST_STATION, vm.uiState.value.step)

        // The station step waits for the fix only so long, then stands in with 中正.
        vm.loadClosestStation()
        advanceTimeBy(OnboardingViewModel.LOCATE_TIMEOUT_MILLIS + 1)
        runCurrent()
        assertTrue((vm.uiState.value.closest as ClosestState.Loaded).station.isFallback)
    }

    @Test
    fun refusingLocationMovesOnAtOnce() = runTest(dispatcher) {
        val vm = model()
        vm.walkTo(OnboardingStep.LOCATION)
        vm.locationAsked()
        vm.locationAnswered(granted = false, prompted = true)
        runCurrent()

        assertEquals(PermissionState.OFF, vm.uiState.value.location)
        assertEquals(OnboardingStep.CLOSEST_STATION, vm.uiState.value.step)
        assertTrue(events.contains(Analytics.ONBOARDING_LOCATION to mapOf("label" to "off")))
    }

    @Test
    fun aPromptInFlightKeepsAskingWhenTheAppResumes() {
        val vm = model()
        vm.locationAsked()
        vm.permissionsChanged(PermissionState.NOT_ASKED, PermissionState.ON)
        assertEquals(PermissionState.ASKING, vm.uiState.value.location)
        assertEquals(PermissionState.ON, vm.uiState.value.notifications)
    }

    // Closest station (step 3)

    @Test
    fun withoutLocationTheStandInIsNearestZhongzheng() = runTest(dispatcher) {
        val vm = model()
        vm.loadClosestStation()
        runCurrent()

        val loaded = vm.uiState.value.closest as ClosestState.Loaded
        assertEquals(2, loaded.station.pollutant.stationId)
        assertTrue(loaded.station.isFallback)
        assertEquals(2, vm.uiState.value.stations.size)
    }

    @Test
    fun withLocationOnTheNearestStationIsFound() = runTest(dispatcher) {
        val vm = model(location = PermissionState.ON, fix = GeoPoint(22.63, 120.30))
        vm.loadClosestStation()
        runCurrent()

        val loaded = vm.uiState.value.closest as ClosestState.Loaded
        assertEquals(1, loaded.station.pollutant.stationId)
        assertFalse(loaded.station.isFallback)
    }

    @Test
    fun noStationsFails() = runTest(dispatcher) {
        val vm = model(stations = emptyList())
        vm.loadClosestStation()
        runCurrent()
        assertEquals(ClosestState.Failed, vm.uiState.value.closest)
    }

    @Test
    fun aChosenStationStaysAndIsLoggedOnce() = runTest(dispatcher) {
        val vm = model()
        vm.loadClosestStation()
        runCurrent()
        vm.chooseStation(kaohsiung)
        vm.chooseStation(kaohsiung)
        vm.loadClosestStation()
        runCurrent()

        val loaded = vm.uiState.value.closest as ClosestState.Loaded
        assertEquals(OnboardingClosestStation.Origin.CHOSEN, loaded.station.origin)
        assertEquals(1, events.count { it == Analytics.ONBOARDING_CHOOSE_STATION to mapOf("stationId" to 1) })
    }

    @Test
    fun turningLocationOnLaterReplacesTheStandIn() = runTest(dispatcher) {
        val vm = model(fix = GeoPoint(22.63, 120.30))
        vm.loadClosestStation()
        runCurrent()
        assertTrue((vm.uiState.value.closest as ClosestState.Loaded).station.isFallback)

        // Back to the location step, and allowed there.
        vm.walkTo(OnboardingStep.LOCATION)
        vm.locationAnswered(granted = true, prompted = true)
        runCurrent()
        // The fix came at once: the nearest station replaces the stand-in without the step asking again.
        assertEquals(1, (vm.uiState.value.closest as ClosestState.Loaded).station.pollutant.stationId)
        vm.loadClosestStation()
        runCurrent()
        assertEquals(1, (vm.uiState.value.closest as ClosestState.Loaded).station.pollutant.stationId)
    }

    /** #77 review: a fix slower than the success pause lands after the step already asked; no endless spinner. */
    @Test
    fun aSlowFixAfterTheStepAskedReplacesTheStandIn() = runTest(dispatcher) {
        val slowFix = OnboardingViewModel.SUCCESS_PAUSE_MILLIS + 2_000
        val vm = model(locate = {
            delay(slowFix)
            GeoPoint(22.63, 120.30)
        })
        // Location refused: the station step stands in with 中正.
        vm.walkTo(OnboardingStep.LOCATION)
        vm.locationAnswered(granted = false, prompted = true)
        runCurrent()
        vm.loadClosestStation()
        runCurrent()
        assertTrue((vm.uiState.value.closest as ClosestState.Loaded).station.isFallback)

        // Back, allowed now; the flow moves on after the pause, and the step asks while the
        // stand-in still shows, so loadClosestStation returns at once.
        vm.goBack()
        vm.locationAnswered(granted = true, prompted = true)
        advanceTimeBy(OnboardingViewModel.SUCCESS_PAUSE_MILLIS + 1)
        runCurrent()
        assertEquals(OnboardingStep.CLOSEST_STATION, vm.uiState.value.step)
        vm.loadClosestStation()
        runCurrent()
        assertTrue((vm.uiState.value.closest as ClosestState.Loaded).station.isFallback)

        // The fix arrives afterwards: the nearest station shows, not a spinner.
        advanceTimeBy(slowFix)
        runCurrent()
        val loaded = vm.uiState.value.closest as ClosestState.Loaded
        assertEquals(1, loaded.station.pollutant.stationId)
        assertFalse(loaded.station.isFallback)
    }

    @Test
    fun aSlowFixKeepsAStationTheReaderChose() = runTest(dispatcher) {
        val slowFix = OnboardingViewModel.SUCCESS_PAUSE_MILLIS + 2_000
        val vm = model(locate = {
            delay(slowFix)
            GeoPoint(22.63, 120.30)
        })
        vm.loadClosestStation()
        runCurrent()
        vm.walkTo(OnboardingStep.LOCATION)
        vm.locationAnswered(granted = true, prompted = true)
        advanceTimeBy(OnboardingViewModel.SUCCESS_PAUSE_MILLIS + 1)
        runCurrent()
        vm.chooseStation(kaohsiung)
        // Chosen over the stand-in, before the fix.
        assertEquals(
            OnboardingClosestStation.Origin.CHOSEN,
            (vm.uiState.value.closest as ClosestState.Loaded).station.origin
        )

        advanceTimeBy(slowFix)
        runCurrent()
        val loaded = vm.uiState.value.closest as ClosestState.Loaded
        assertEquals(OnboardingClosestStation.Origin.CHOSEN, loaded.station.origin)
        assertEquals(1, loaded.station.pollutant.stationId)
    }

    // Notifications (step 4)

    @Test
    fun allowingNotificationsStaysForQuietHours() {
        val vm = model()
        vm.walkTo(OnboardingStep.NOTIFICATIONS)
        assertFalse(vm.uiState.value.showsQuietHours)
        vm.notificationsAsked()
        vm.notificationsAnswered(accepted = true)

        assertEquals(OnboardingStep.NOTIFICATIONS, vm.uiState.value.step)
        assertTrue(vm.uiState.value.showsQuietHours)
        assertEquals(Analytics.ONBOARDING_NOTIFICATIONS to mapOf("label" to "on"), events.last())
    }

    @Test
    fun refusingNotificationsMovesOn() {
        val vm = model()
        vm.walkTo(OnboardingStep.NOTIFICATIONS)
        vm.notificationsAsked()
        vm.notificationsAnswered(accepted = false)

        assertEquals(OnboardingStep.MORE, vm.uiState.value.step)
        assertFalse(vm.uiState.value.showsQuietHours)
        assertTrue(events.contains(Analytics.ONBOARDING_NOTIFICATIONS to mapOf("label" to "off")))
    }

    @Test
    fun proAndFavouriteEventsMatchIos() {
        val vm = model()
        vm.favouriteAdded(91)
        vm.proOpened()
        assertEquals(Analytics.ONBOARDING_ADD_FAVOURITE to mapOf("stationId" to 91), events[events.size - 2])
        assertEquals(Analytics.ONBOARDING_OPEN_PRO, events.last().first)
    }
}
