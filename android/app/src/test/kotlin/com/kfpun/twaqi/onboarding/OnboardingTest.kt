package com.kfpun.twaqi.onboarding

import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.ui.main.GeoPoint
import com.kfpun.twaqi.widget.WidgetLocation
import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `OnboardingTests` (FOX-34, FOX-49, FOX-84), with what Android has. */
class OnboardingTest {
    private class MemoryFlags(override var shownVersion: Int = 0) : OnboardingFlags

    @After
    fun tearDown() {
        Onboarding.resetForTests()
    }

    // Shown once

    @Test
    fun freshInstallShowsTheFlow() {
        val store = OnboardingStore(MemoryFlags())
        assertTrue(store.showsOnLaunch)
        assertEquals(0, store.shownVersion)
    }

    @Test
    fun shownPersistsUnderTheVersionedKey() {
        val flags = MemoryFlags()
        OnboardingStore(flags).markShown()

        assertEquals(OnboardingStore.CURRENT_VERSION, flags.shownVersion)
        assertEquals("onboardingShownVersion", OnboardingStore.KEY_SHOWN_VERSION)
        assertEquals(1, OnboardingStore.CURRENT_VERSION)
        // A new store over the same settings, as on the next launch or after an update.
        assertFalse(OnboardingStore(flags).showsOnLaunch)
    }

    @Test
    fun quitMidFlowIsNotShownAgain() {
        // Marked when it opens; the app is killed before Done or Skip.
        val flags = MemoryFlags()
        OnboardingStore(flags).markShown()
        assertFalse(OnboardingStore(flags).showsOnLaunch)
    }

    @Test
    fun raisingTheVersionShowsItOnceMore() {
        val flags = MemoryFlags()
        OnboardingStore(flags, currentVersion = 1).markShown()

        val reworked = OnboardingStore(flags, currentVersion = 2)
        assertTrue(reworked.showsOnLaunch)
        reworked.markShown()
        assertFalse(OnboardingStore(flags, currentVersion = 2).showsOnLaunch)
    }

    @Test
    fun markShownRecordsOnlyTheFirstTime() {
        val store = OnboardingStore(MemoryFlags())
        assertTrue(store.markShown())
        // A second composition of the same run.
        assertFalse(store.markShown())
    }

    @Test
    fun markShownNeverLowersTheVersion() {
        val flags = MemoryFlags()
        OnboardingStore(flags, currentVersion = 2).markShown()
        OnboardingStore(flags, currentVersion = 1).markShown()
        assertEquals(2, OnboardingStore(flags).shownVersion)
    }

    // Launch hold

    @Test
    fun theLaunchIsDecidedOncePerProcess() {
        assertTrue(Onboarding.decideLaunch(showsOnLaunch = true))
        assertTrue(Onboarding.isOpenAtLaunch.value)
        // A recreated activity, after the flow marked itself shown: still the same run.
        assertTrue(Onboarding.decideLaunch(showsOnLaunch = false))
    }

    @Test
    fun noHoldWhenTheFlowDoesNotShow() {
        assertFalse(Onboarding.decideLaunch(showsOnLaunch = false))
        assertFalse(Onboarding.isOpenAtLaunch.value)
    }

    @Test
    fun finishingAHelpRunLeavesTheLaunchHold() {
        Onboarding.decideLaunch(showsOnLaunch = true)
        Onboarding.flowEnded(isLaunchFlow = false)
        assertTrue(Onboarding.isOpenAtLaunch.value)
    }

    @Test
    fun finishingTheLaunchRunReleasesTheHold() {
        Onboarding.decideLaunch(showsOnLaunch = true)
        Onboarding.flowEnded(isLaunchFlow = true)
        assertFalse(Onboarding.isOpenAtLaunch.value)
        // Once released, a later decision doesn't bring it back.
        assertFalse(Onboarding.decideLaunch(showsOnLaunch = true))
    }

    // Steps (FOX-84: five at most)

    @Test
    fun stepOrder() {
        assertEquals(
            listOf(
                OnboardingStep.WELCOME,
                OnboardingStep.LOCATION,
                OnboardingStep.CLOSEST_STATION,
                OnboardingStep.NOTIFICATIONS,
                OnboardingStep.MORE
            ),
            OnboardingStep.entries
        )
        assertTrue(OnboardingStep.entries.size <= 5)
        assertNull(OnboardingStep.WELCOME.previous)
        assertTrue(OnboardingStep.MORE.isLast)
        assertNull(OnboardingStep.MORE.next)
        assertFalse(OnboardingStep.NOTIFICATIONS.isLast)
    }

    @Test
    fun nextAndPreviousWalkTheOrder() {
        assertEquals(OnboardingStep.LOCATION, OnboardingStep.WELCOME.next)
        assertEquals(OnboardingStep.CLOSEST_STATION, OnboardingStep.LOCATION.next)
        assertEquals(OnboardingStep.NOTIFICATIONS, OnboardingStep.CLOSEST_STATION.next)
        assertEquals(OnboardingStep.MORE, OnboardingStep.NOTIFICATIONS.next)

        assertEquals(OnboardingStep.NOTIFICATIONS, OnboardingStep.MORE.previous)
        assertEquals(OnboardingStep.CLOSEST_STATION, OnboardingStep.NOTIFICATIONS.previous)
        assertEquals(OnboardingStep.LOCATION, OnboardingStep.CLOSEST_STATION.previous)
        assertEquals(OnboardingStep.WELCOME, OnboardingStep.LOCATION.previous)

        OnboardingStep.entries.forEach { step -> step.next?.let { assertEquals(step, it.previous) } }
    }

    @Test
    fun analyticsNamesFollowTheIosOrder() {
        assertEquals(
            listOf("welcome", "location", "closest_station", "notifications", "more"),
            OnboardingStep.entries.map { it.analyticsName }
        )
        assertEquals(listOf(1, 2, 3, 4, 5), OnboardingStep.entries.map { it.analyticsIndex })
    }

    @Test
    fun eventNamesMatchIos() {
        assertEquals(
            listOf(
                "onboarding_shown",
                "onboarding_step_viewed",
                "onboarding_location",
                "onboarding_notifications",
                "onboarding_add_favourite",
                "onboarding_choose_station",
                "onboarding_open_pro",
                "onboarding_skipped",
                "onboarding_completed",
                "onboarding_open_from_help"
            ),
            listOf(
                Analytics.ONBOARDING_SHOWN,
                Analytics.ONBOARDING_STEP_VIEWED,
                Analytics.ONBOARDING_LOCATION,
                Analytics.ONBOARDING_NOTIFICATIONS,
                Analytics.ONBOARDING_ADD_FAVOURITE,
                Analytics.ONBOARDING_CHOOSE_STATION,
                Analytics.ONBOARDING_OPEN_PRO,
                Analytics.ONBOARDING_SKIPPED,
                Analytics.ONBOARDING_COMPLETED,
                Analytics.ONBOARDING_OPEN_FROM_HELP
            )
        )
    }

    // Notifications with quiet hours

    @Test
    fun quietHoursShowOnceNotificationsAreOn() {
        assertTrue(Onboarding.showsQuietHours(notificationsOn = true))
        assertFalse(Onboarding.showsQuietHours(notificationsOn = false))
    }

    @Test
    fun allowingNotificationsStaysForQuietHours() {
        assertFalse(Onboarding.advancesAfterNotificationAnswer(accepted = true))
        assertTrue(Onboarding.advancesAfterNotificationAnswer(accepted = false))
    }

    @Test
    fun permissionStateFromWhatAndroidSays() {
        assertEquals(PermissionState.ON, PermissionState.of(granted = true, asked = false))
        assertEquals(PermissionState.ON, PermissionState.of(granted = true, asked = true))
        assertEquals(PermissionState.OFF, PermissionState.of(granted = false, asked = true))
        assertEquals(PermissionState.NOT_ASKED, PermissionState.of(granted = false, asked = false))
    }

    // Choosing another station

    @Test
    fun stationListGroupsByAreaInFirstSeenOrder() {
        val stations = listOf(
            station(1, 25.0, 121.5, name = "Songshan", area = "North"),
            station(2, 22.6, 120.3, name = "Qianzhen", area = "Kaoping"),
            station(3, 25.1, 121.6, name = "Shilin", area = "North")
        )

        val sections = OnboardingStationList.sections(stations, "", chinese = false)
        assertEquals(listOf("North", "Kaoping"), sections.map { it.title })
        assertEquals(listOf(1, 3), sections[0].stations.map { it.stationId })
        assertEquals(listOf(2), sections[1].stations.map { it.stationId })
        // The area in the reader's language.
        assertEquals(
            listOf("North區", "Kaoping區"),
            OnboardingStationList.sections(stations, "", chinese = true).map {
                it.title
            }
        )
    }

    @Test
    fun stationListSearchesBothLanguagesAndDropsEmptyAreas() {
        val stations = listOf(
            station(1, 25.0, 121.5, name = "Songshan", area = "North"),
            station(2, 22.6, 120.3, name = "Qianzhen", area = "Kaoping")
        )

        assertEquals(
            listOf(1),
            OnboardingStationList.sections(stations, "song", false).flatMap {
                it.stations
            }.map { it.stationId }
        )
        // The Chinese name matches whatever the UI language.
        assertEquals(
            listOf(2),
            OnboardingStationList.sections(stations, "測站2", false).flatMap {
                it.stations
            }.map { it.stationId }
        )
        assertEquals(2, OnboardingStationList.sections(stations, "  ", false).size)
        assertTrue(OnboardingStationList.sections(stations, "nowhere", false).isEmpty())
    }

    @Test
    fun chosenStationIsNotAStandIn() {
        val chosen = OnboardingClosestStation(station(9, 25.0, 121.5), OnboardingClosestStation.Origin.CHOSEN)
        assertFalse(chosen.isFallback)
    }

    // Closest station / 中正 fallback

    @Test
    fun withoutLocationFallsBackToStationNearestZhongzheng() {
        val stations = listOf(
            station(1, 22.6273, 120.3014), // Kaohsiung
            station(2, 25.0330, 121.5150), // next to 中正區
            station(3, 25.0600, 121.5800) // Songshan, further off
        )

        val resolved = assertNotNullAnd(OnboardingClosestStation.resolve(null, stations))
        assertEquals(2, resolved.pollutant.stationId)
        assertTrue(resolved.isFallback)
    }

    @Test
    fun fallbackUsesTheWidgetsDefault() {
        // One shared definition: the point the widgets (and iOS's Watch app) fall back to.
        val stations = listOf(
            station(7, WidgetLocation.DEFAULT.lat, WidgetLocation.DEFAULT.lon),
            station(8, 25.10, 121.60)
        )
        assertEquals(7, OnboardingClosestStation.resolve(null, stations)?.pollutant?.stationId)
    }

    @Test
    fun withLocationPicksNearestStation() {
        val stations = listOf(station(1, 22.6273, 120.3014), station(2, 25.0330, 121.5150))

        val resolved = assertNotNullAnd(OnboardingClosestStation.resolve(GeoPoint(22.63, 120.30), stations))
        assertEquals(1, resolved.pollutant.stationId)
        assertFalse(resolved.isFallback)
    }

    @Test
    fun noStationsResolvesToNothing() {
        assertNull(OnboardingClosestStation.resolve(null, emptyList()))
    }

    // Animations

    @Test
    fun everyAnimationIsTheIosFileUnchanged() {
        OnboardingAnimation.entries.forEach { animation ->
            val android = File("src/main/assets/${animation.assetPath}")
            val ios = File("../../ios/TWAQI/OnboardingAnimations/${animation.fileName}.json")
            assertTrue(android.path, android.isFile)
            assertTrue(ios.path, ios.isFile)
            assertArrayEquals(animation.fileName, ios.readBytes(), android.readBytes())
        }
        OnboardingStep.entries.forEach { assertTrue(it.animation != OnboardingAnimation.SUCCESS) }
    }

    @Test
    fun animationsStaySmall() {
        val sizes = OnboardingAnimation.entries.map { File("src/main/assets/${it.assetPath}").length() }
        sizes.forEach { assertTrue(it < 100 * 1024) }
        assertTrue(sizes.sum() < 500 * 1024)
    }

    @Test
    fun animationsReachLottieAndroidWithTheTypeFirstAndNothingElseChanged() {
        OnboardingAnimation.entries.forEach { animation ->
            val original = File("src/main/assets/${animation.assetPath}").readText()
            val forAndroid = OnboardingAnimationJson.forLottieAndroid(original)
            // The same tree (JsonObject equality ignores key order)...
            assertEquals(animation.fileName, Json.parseToJsonElement(original), Json.parseToJsonElement(forAndroid))
            // ...with "ty" leading every object that has one, shapes and groups included.
            var typed = 0
            fun check(element: JsonElement) {
                when (element) {
                    is JsonObject -> {
                        if ("ty" in element) {
                            typed++
                            assertEquals(animation.fileName, "ty", element.keys.first())
                        }
                        element.values.forEach(::check)
                    }

                    is JsonArray -> element.forEach(::check)

                    else -> Unit
                }
            }
            check(Json.parseToJsonElement(forAndroid))
            assertTrue(animation.fileName, typed > 3)
        }
    }

    @Test
    fun typeMovesToTheFrontOfNestedObjects() {
        val json = """{"it":[{"d":1,"s":{"a":0,"k":[16,19]},"ty":"el"}],"nm":"eye","ty":"gr"}"""
        assertEquals(
            """{"ty":"gr","it":[{"ty":"el","d":1,"s":{"a":0,"k":[16,19]}}],"nm":"eye"}""",
            OnboardingAnimationJson.forLottieAndroid(json)
        )
    }

    // Reduce Motion

    @Test
    fun removedAnimationsShowTheLastFrameStill() {
        assertTrue(OnboardingMotion.reducesMotion(0f))
        assertEquals(1f, OnboardingMotion.stillProgress(0f))
        // iOS `.paused(at: .progress(1))`: the drawing complete.
        assertEquals(1f, OnboardingMotion.STILL_PROGRESS)
    }

    @Test
    fun anyOtherScalePlaysTheAnimation() {
        listOf(1f, 0.5f, 2f, 10f).forEach { scale ->
            assertFalse(OnboardingMotion.reducesMotion(scale))
            assertNull(OnboardingMotion.stillProgress(scale))
        }
    }

    private fun <T : Any> assertNotNullAnd(value: T?): T {
        assertNotNull(value)
        return value!!
    }

    companion object {
        fun station(id: Int, lat: Double, lon: Double, name: String? = null, area: String? = null) = Pollutant(
            stationId = id,
            code = "S$id",
            lat = lat,
            lon = lon,
            aqi = 42.0,
            pm25 = 10.0,
            pm10 = 20.0,
            no2 = 1.0,
            so2 = 1.0,
            co = 0.1,
            o3 = 30.0,
            windDirection = 0.0,
            windSpeed = 0.0,
            publishTime = "2026-11-02 10:00:00",
            name = name ?: "Station $id",
            nameLocal = "測站$id",
            area = area,
            areaLocal = area?.let { "${it}區" }
        )
    }
}
