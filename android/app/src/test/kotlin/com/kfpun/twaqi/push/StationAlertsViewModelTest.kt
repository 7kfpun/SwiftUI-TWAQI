package com.kfpun.twaqi.push

import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.locale.AppLanguage
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** iOS `SettingsRowViewModel`: the station page's switches, the limit, and changes from elsewhere. */
@OptIn(ExperimentalCoroutinesApi::class)
class StationAlertsViewModelTest {
    private val dispatcher = UnconfinedTestDispatcher()
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private val above =
        StationAlertSetting(isPollutionNotificationEnabled = true, isCleanlinessNotificationEnabled = false)

    @Before
    fun setUp() = Dispatchers.setMain(dispatcher)

    @After
    fun tearDown() {
        scope.cancel()
        Dispatchers.resetMain()
    }

    private fun model(
        store: FakeAlertStore,
        favourites: FakeFavourites = FakeFavourites(),
        logger: RecordingLogger = RecordingLogger()
    ): Pair<StationAlertsViewModel, FavouriteAlerts> {
        val alerts = FavouriteAlerts(store, { favourites }, { false }, logger, scope)
        return StationAlertsViewModel(126, null, alerts, logger) to alerts
    }

    @Test
    fun switchingOnSavesAndMakesTheStationAFavourite() {
        val store = FakeAlertStore()
        val favourites = FakeFavourites(listOf(5))
        val (vm, _) = model(store, favourites)

        assertTrue(vm.onChange(above))
        assertEquals(StationAlerts(above = 120), store.alerts(126))
        assertEquals(listOf(5, 126), favourites.list)
        assertTrue(vm.uiState.value.setting.isPollutionNotificationEnabled)
    }

    @Test
    fun otherStationsAtTheLimitLockTheSwitchesAndSaySo() {
        val logger = RecordingLogger()
        val store = FakeAlertStore(
            mapOf(
                1 to StationAlerts(above = 100),
                2 to StationAlerts(above = 100),
                3 to StationAlerts(below = 30)
            )
        )
        val (vm, _) = model(store, logger = logger)

        val state = vm.uiState.value
        assertTrue(state.isAtCap)
        assertTrue(state.pollutionLocked && state.cleanlinessLocked)
        // Logged once per page.
        assertEquals(listOf(Analytics.ALERT_LIMIT_SHOWN), logger.events.map { it.first })

        // A switch that slipped through (another screen) goes back off, and nothing is saved.
        assertFalse(vm.onChange(above))
        assertFalse(vm.uiState.value.setting.isOn)
        assertNull(store.alertedStations.value[126])
        assertEquals(1, logger.events.count { it.first == Analytics.ALERT_LIMIT_SHOWN })
    }

    @Test
    fun aStationThatIsOnStaysSwitchableAtTheLimit() {
        val store = FakeAlertStore(
            mapOf(
                1 to StationAlerts(above = 100),
                2 to StationAlerts(above = 100),
                126 to StationAlerts(above = 120)
            )
        )
        val (vm, _) = model(store)
        assertFalse(vm.uiState.value.isAtCap)

        assertTrue(vm.onChange(StationAlertSetting.OFF))
        assertNull(store.alertedStations.value[126])
        // Others are at the limit now, so the switches lock.
        store.stationChanged(3, null, StationAlerts(below = 20), settled = true)
        assertTrue(vm.uiState.value.isAtCap)
    }

    @Test
    fun clearedFromFavouritesTheSwitchesGoOff() {
        val store = FakeAlertStore(mapOf(126 to StationAlerts(above = 150, below = 20)))
        val (vm, alerts) = model(store)
        assertTrue(vm.uiState.value.setting.isOn)

        alerts.clear(126)
        assertFalse(vm.uiState.value.setting.isOn)
        // The thresholds are kept for the next time a switch goes on.
        assertEquals(150.0, vm.uiState.value.setting.pollutionThreshold, 0.0)
    }

    @Test
    fun switchedOnByFavouritingTheSwitchesFollow() {
        val store = FakeAlertStore()
        val (vm, alerts) = model(store)

        alerts.enableForNewFavourite(126, null) { true }
        assertEquals(FavouriteAlerts.DEFAULT_ALERTS, vm.uiState.value.setting)
    }

    @Test
    fun pushLocaleIsTheAppLanguage() {
        assertEquals("zh-Hant", AppDeviceProfile.pushLocale(AppLanguage.TRADITIONAL_CHINESE, Locale.US))
        assertEquals("en", AppDeviceProfile.pushLocale(AppLanguage.ENGLISH, Locale.TAIWAN))
        // Following the phone: one of the two languages the app has.
        assertEquals("zh-Hant", AppDeviceProfile.pushLocale(AppLanguage.SYSTEM, Locale.TAIWAN))
        assertEquals("en", AppDeviceProfile.pushLocale(AppLanguage.SYSTEM, Locale.JAPAN))
    }

    @Test
    fun notificationsAllowedIsUnknownUntilAsked() {
        assertEquals(
            true,
            AppDeviceProfile.notificationsAllowed(
                enabled = true,
                needsPermission = true,
                permissionGranted = true,
                asked = true
            )
        )
        // Android 13+, never asked: unknown, not "no".
        assertNull(
            AppDeviceProfile.notificationsAllowed(
                enabled = false,
                needsPermission = true,
                permissionGranted = false,
                asked = false
            )
        )
        assertEquals(
            false,
            AppDeviceProfile.notificationsAllowed(
                enabled = false,
                needsPermission = true,
                permissionGranted = false,
                asked = true
            )
        )
        // Turned off in Settings.
        assertEquals(
            false,
            AppDeviceProfile.notificationsAllowed(
                enabled = false,
                needsPermission = false,
                permissionGranted = true,
                asked = false
            )
        )
    }
}
