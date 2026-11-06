package com.kfpun.twaqi.onboarding

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.ui.main.GeoPoint
import com.kfpun.twaqi.ui.main.MapPreferences
import com.kfpun.twaqi.ui.main.NearestStations
import com.kfpun.twaqi.ui.main.StationSearch
import com.kfpun.twaqi.widget.WidgetLocation
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/**
 * The welcome flow (iOS `Onboarding`, FOX-34 / FOX-84): opens by itself once for every user, and
 * again whenever it is opened from Help.
 */
object Onboarding {
    private val openAtLaunch = MutableStateFlow(false)

    /**
     * The flow opened by itself on this launch and isn't finished yet. The map holds back its
     * location request and the review prompt waits until then, so neither stacks over the flow
     * (iOS `isOpenAtLaunch` and `didFinish`).
     */
    val isOpenAtLaunch: StateFlow<Boolean> = openAtLaunch.asStateFlow()

    /** Decided once per process, before anything is shown; a recreated activity keeps the answer. */
    private var launchDecided = false

    /**
     * Whether this process opens the flow by itself, decided on its first call only (iOS decides in
     * `AppDelegate`, once per launch). Sets [isOpenAtLaunch].
     */
    @Synchronized
    fun decideLaunch(showsOnLaunch: Boolean): Boolean {
        if (!launchDecided) {
            launchDecided = true
            openAtLaunch.value = showsOnLaunch
        }
        return openAtLaunch.value
    }

    /** Ends the launch-time hold, once. */
    fun releaseLaunchHold() {
        openAtLaunch.value = false
    }

    /**
     * The flow was finished or skipped. Only the run that opened by itself at launch ends the hold;
     * a run from Help leaves it alone.
     */
    fun flowEnded(isLaunchFlow: Boolean) {
        if (isLaunchFlow) releaseLaunchHold()
    }

    /** Quiet hours show on the notifications step once notifications are on: before that they would silence nothing. */
    fun showsQuietHours(notificationsOn: Boolean): Boolean = notificationsOn

    /** After the notification prompt is answered: a yes stays on the step so quiet hours can be set there, a no moves on. */
    fun advancesAfterNotificationAnswer(accepted: Boolean): Boolean = !accepted

    /** For tests: forget this process's launch decision. */
    internal fun resetForTests() {
        launchDecided = false
        openAtLaunch.value = false
    }
}

/**
 * The steps, in order, five at most (FOX-84). Location is asked for on [LOCATION] only, and
 * notifications on [NOTIFICATIONS] only. The data source is a line on [WELCOME], quiet hours sit on
 * [NOTIFICATIONS], and [MORE] shows the widgets, the shortcuts and the Forecast tab above Pro.
 */
enum class OnboardingStep(
    /** As `onboarding_step_viewed` names it (iOS `analyticsName`). */
    val analyticsName: String,
    /** The animation at the top of the step. */
    val animation: OnboardingAnimation
) {
    WELCOME("welcome", OnboardingAnimation.WELCOME),
    LOCATION("location", OnboardingAnimation.LOCATION),
    CLOSEST_STATION("closest_station", OnboardingAnimation.CLOSEST_STATION),
    NOTIFICATIONS("notifications", OnboardingAnimation.NOTIFICATIONS),
    MORE("more", OnboardingAnimation.MORE);

    val next: OnboardingStep? get() = entries.getOrNull(ordinal + 1)
    val previous: OnboardingStep? get() = entries.getOrNull(ordinal - 1)
    val isLast: Boolean get() = next == null

    /** 1-based, as the dots and `onboarding_skipped`'s step_<n> count. */
    val analyticsIndex: Int get() = ordinal + 1
}

/** Where the shown version is kept. */
interface OnboardingFlags {
    /** The highest flow version that has opened by itself; 0 for none. */
    var shownVersion: Int
}

/**
 * Which version of the welcome flow has opened by itself (iOS `OnboardingStore`), in the app's
 * settings file, so it follows the user to a new phone with the rest of their settings.
 *
 * iOS's other keys don't apply here: no Android build asks for notifications at launch (the
 * legacy-install prompt), and none ran the FOX-34 flow whose `onboardingCompleted` iOS carries over.
 */
class OnboardingStore(private val flags: OnboardingFlags, private val currentVersion: Int = CURRENT_VERSION) {
    constructor(context: Context) : this(SharedPreferencesOnboardingFlags(context))

    val shownVersion: Int get() = flags.shownVersion

    /** Whether the flow should open by itself at launch: this version of it never has. */
    val showsOnLaunch: Boolean get() = shownVersion < currentVersion

    /**
     * The flow opened by itself: it won't again until the version is raised. Help's runs don't call
     * this. Returns whether this call recorded it, so a recomposition is counted once.
     */
    fun markShown(): Boolean {
        if (shownVersion >= currentVersion) return false
        flags.shownVersion = currentVersion
        return true
    }

    companion object {
        /** The flow's version (iOS `OnboardingStore.currentVersion`). Raise it to open a reworked flow once more for everyone. */
        const val CURRENT_VERSION = 1

        /** The iOS defaults key. */
        const val KEY_SHOWN_VERSION = "onboardingShownVersion"
    }
}

/** The settings file (`MapPreferences.PREFS`), backed up with the language and the map. */
class SharedPreferencesOnboardingFlags(private val prefs: SharedPreferences) : OnboardingFlags {
    constructor(context: Context) : this(
        context.applicationContext.getSharedPreferences(MapPreferences.PREFS, Context.MODE_PRIVATE)
    )

    override var shownVersion: Int
        get() = prefs.getInt(OnboardingStore.KEY_SHOWN_VERSION, 0)
        set(value) = prefs.edit { putInt(OnboardingStore.KEY_SHOWN_VERSION, value) }
}

/** The station the flow suggests as a first favourite (iOS `OnboardingClosestStation`). */
data class OnboardingClosestStation(val pollutant: Pollutant, val origin: Origin) {
    enum class Origin {
        /** Nearest the reader's location. */
        NEAREST,

        /** No location: the station nearest 中正, standing in until the reader picks their own. */
        FALLBACK,

        /** Picked from the list. */
        CHOSEN
    }

    val isFallback: Boolean get() = origin == Origin.FALLBACK

    companion object {
        /**
         * The station nearest [location], or, without one, nearest the same 中正 point the widgets
         * fall back to ([WidgetLocation.DEFAULT], iOS `WatchAPI.defaultLocation`).
         */
        fun resolve(location: GeoPoint?, stations: List<Pollutant>): OnboardingClosestStation? {
            val pollutant = NearestStations.closest(stations, location ?: WidgetLocation.DEFAULT) ?: return null
            return OnboardingClosestStation(pollutant, if (location == null) Origin.FALLBACK else Origin.NEAREST)
        }
    }
}

/** The closest station step's list for choosing another station: search, or browse by 空品區. */
object OnboardingStationList {
    data class Section(val title: String, val stations: List<Pollutant>)

    /**
     * Stations matching [query] as the station list's search matches them ([StationSearch]: either
     * language's name, township or county), grouped by air-quality area in first-seen (roughly
     * north-to-south) order. An empty query keeps every station.
     */
    fun sections(stations: List<Pollutant>, query: String, chinese: Boolean): List<Section> =
        StationSearch.filter(stations, query)
            .groupBy { it.displayArea(chinese).orEmpty() }
            .map { (title, list) -> Section(title, list) }
}

/**
 * The flow's Lottie animations (iOS `OnboardingAnimation`, FOX-84), drawn for TWAQI by
 * `tools/make_onboarding_animations.py` and copied unchanged into `assets/onboarding/`.
 * Nothing is downloaded.
 */
enum class OnboardingAnimation(private val key: String) {
    WELCOME("welcome"),
    LOCATION("location"),
    CLOSEST_STATION("closest_station"),
    NOTIFICATIONS("notifications"),
    MORE("more"),
    SUCCESS("success");

    val fileName: String get() = "onboarding_$key"

    /** The path under `assets/`. */
    val assetPath: String get() = "$DIRECTORY/$fileName.json"

    companion object {
        const val DIRECTORY = "onboarding"
    }
}

/**
 * Reduce Motion for the animations: with animations removed (animator duration scale 0, which the
 * "Remove animations" setting sets), each shows one still frame, the last, as iOS does
 * (`.paused(at: .progress(1))`), so the drawing is complete.
 */
object OnboardingMotion {
    /** The frame shown still, as progress (iOS `.progress(1)`). */
    const val STILL_PROGRESS = 1f

    fun reducesMotion(animatorDurationScale: Float): Boolean = animatorDurationScale == 0f

    /** The progress to draw still, or null to play the animation once. */
    fun stillProgress(animatorDurationScale: Float): Float? =
        if (reducesMotion(animatorDurationScale)) STILL_PROGRESS else null
}

/**
 * The iOS animation files as lottie-android reads them. The files are written with their keys in
 * sorted order, so each shape's `"ty"` comes after its properties and each group's `"it"` before
 * its `"ty"`. lottie-ios doesn't mind; lottie-android's shape parser skips every key it meets
 * before `"ty"`, which leaves every shape empty and the animation blank. Moving `"ty"` to the front
 * of each object, in memory, fixes that and keeps the bundled files byte for byte the iOS ones.
 */
object OnboardingAnimationJson {
    fun forLottieAndroid(json: String): String = typeFirst(Json.parseToJsonElement(json)).toString()

    internal fun typeFirst(element: JsonElement): JsonElement = when (element) {
        is JsonObject -> {
            val ordered = LinkedHashMap<String, JsonElement>()
            element[TYPE]?.let { ordered[TYPE] = it }
            element.forEach { (key, value) -> if (key != TYPE) ordered[key] = typeFirst(value) }
            JsonObject(ordered)
        }

        is JsonArray -> JsonArray(element.map(::typeFirst))

        else -> element
    }

    private const val TYPE = "ty"
}
