package com.kfpun.twaqi.shortcuts

import android.content.Context
import android.content.res.Configuration
import android.os.LocaleList
import android.util.Log
import androidx.annotation.StringRes
import androidx.core.content.edit
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.StationText
import com.kfpun.twaqi.locale.AppLocale
import com.kfpun.twaqi.ui.navigation.DeepLink
import com.kfpun.twaqi.ui.navigation.StationLinkSource
import com.kfpun.twaqi.widget.WidgetDataSource
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Which stations get a launcher shortcut (FOX-95), apart from Android so the order and the cap
 * are unit tested.
 */
object StationShortcutPlan {
    /**
     * At most this many station shortcuts, whatever the launcher allows: a long-press menu shows
     * about five entries, and the "Air quality" shortcut is one of them.
     */
    const val MAX_STATIONS = 4

    /** Shortcuts other than stations ("Air quality"), which count against the launcher's limit. */
    const val OTHER_SHORTCUTS = 1

    /** How many station shortcuts fit: the launcher's per-activity limit less the other ones, capped. */
    fun limit(launcherMax: Int, otherCount: Int = OTHER_SHORTCUTS): Int =
        minOf(MAX_STATIONS, launcherMax - otherCount).coerceAtLeast(0)

    /**
     * Favourites in the reader's order, then recently opened stations, newest first, without
     * repeats, at most [limit]. When favourites alone would fill every slot, the last one goes
     * to the newest recent station that isn't a favourite, so a station looked up once is still
     * a long-press away.
     */
    fun stationIds(favouriteIds: List<Int>, recentIds: List<Int>, limit: Int): List<Int> {
        if (limit <= 0) return emptyList()
        val favourites = favouriteIds.filter { it > 0 }.distinct()
        val recents = recentIds.filter { it > 0 && it !in favourites }.distinct()
        val favouriteSlots = if (recents.isNotEmpty() && limit > 1) minOf(favourites.size, limit - 1) else limit
        val chosen = favourites.take(favouriteSlots)
        return (chosen + recents).take(limit)
    }

    /** The shortcut id of a station's shortcut; launchers keep pinned copies by it. */
    fun shortcutId(stationId: Int): String = "$SHORTCUT_PREFIX$stationId"

    /** The "Air quality" shortcut's id. */
    const val AIR_QUALITY_ID = "air_quality"

    private const val SHORTCUT_PREFIX = "station_"
}

/** Stations the reader opened lately, newest first (iOS has no such list; Android's launcher shortcuts use it). */
object RecentStations {
    const val MAX = 5

    /** [stationId] moved to the front of [recent], at most [MAX]. */
    fun record(recent: List<Int>, stationId: Int, max: Int = MAX): List<Int> =
        (listOf(stationId) + recent.filter { it != stationId }).take(max)

    fun read(context: Context): List<Int> =
        prefs(context).getString(KEY, null)?.split(',')?.mapNotNull { it.trim().toIntOrNull() }.orEmpty()

    fun add(context: Context, stationId: Int): List<Int> {
        val updated = record(read(context), stationId)
        prefs(context).edit { putString(KEY, updated.joinToString(",")) }
        return updated
    }

    const val PREFS = "recent_stations"
    private const val KEY = "stationIds"

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}

/**
 * The launcher's shortcuts (FOX-95, the Android side of iOS `TWAQIShortcuts`): "Air quality" first,
 * opening the answer card ([AirQualityAnswerActivity]), then one per favourite and recent station
 * ([StationShortcutPlan]), each opening its station. All go through [DeepLink] and are named in the
 * app's language, so all are dynamic: a launcher names a static (`shortcuts.xml`) shortcut in the
 * phone's language, not the one chosen in Help › Language. Each is also Google Assistant's
 * inventory for `actions.intent.OPEN_APP_FEATURE` (`res/xml/shortcuts.xml`), with its name in
 * both languages.
 *
 * Refreshed at start, when favourites change, when a station is opened, when the app goes to the
 * background (names loaded meanwhile) and when the language changes. Nothing is written when the list is unchanged, which keeps clear of the launcher's
 * rate limit.
 */
object StationShortcuts {
    private const val TAG = "TWAQIShortcuts"
    private const val OPEN_APP_FEATURE = "actions.intent.OPEN_APP_FEATURE"
    private const val FEATURE_PARAMETER = "feature"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mutex = Mutex()

    /** Keeps the shortcuts in step with [favourites]; the first value refreshes them at start. */
    fun observe(context: Context, favourites: Flow<List<Int>>) {
        val app = context.applicationContext
        scope.launch { favourites.collectLatest { refresh(app) } }
    }

    fun requestRefresh(context: Context) {
        val app = context.applicationContext
        scope.launch { refresh(app) }
    }

    /** A station's page opened: it becomes a recent station, and the launcher learns it was used. */
    fun stationOpened(context: Context, stationId: Int) {
        val app = context.applicationContext
        scope.launch {
            RecentStations.add(app, stationId)
            runCatching { ShortcutManagerCompat.reportShortcutUsed(app, StationShortcutPlan.shortcutId(stationId)) }
            refresh(app)
        }
    }

    suspend fun refresh(context: Context) = mutex.withLock {
        runCatching { publish(context) }.onFailure { Log.w(TAG, "Couldn't update shortcuts", it) }
    }

    private suspend fun publish(context: Context) {
        val container = WidgetDataSource.containerOf(context)
        val limit = StationShortcutPlan.limit(ShortcutManagerCompat.getMaxShortcutCountPerActivity(context))
        val ids = StationShortcutPlan.stationIds(
            container.favourites.favourites.value,
            RecentStations.read(context),
            limit
        )
        val readings = container.airQuality.savedPollutants(ids).associate { it.value.stationId to it.value }
        val stations = if (ids.all(readings::containsKey)) {
            emptyMap()
        } else {
            container.airQuality.savedStations()?.value.orEmpty().associateBy { it.id }
        }
        val chinese = AppLocale.isChinese(context)
        val localized = AppLocale.localizedContext(context)
        val icon = IconCompat.createWithResource(context, R.drawable.ic_shortcut_station)
        val airQuality = ShortcutInfoCompat.Builder(context, StationShortcutPlan.AIR_QUALITY_ID)
            .setShortLabel(localized.getString(R.string.intent_get_air_quality_short))
            .setLongLabel(localized.getString(R.string.intent_get_air_quality_title))
            .setIcon(IconCompat.createWithResource(context, R.drawable.ic_shortcut_air_quality))
            .setRank(0)
            .setIntent(AirQualityAnswerActivity.intent(context))
            .addCapabilityBinding(
                OPEN_APP_FEATURE,
                FEATURE_PARAMETER,
                bothLanguages(context, R.string.intent_assistant_feature_air_quality)
            )
            .build()
        val stationShortcuts = ids.mapIndexed { index, id ->
            val (local, english) = readings[id]?.let { it.displayName(true) to it.displayName(false) }
                ?: stations[id]?.let { it.displayName(true) to it.displayName(false) }
                ?: (StationText.displayName("", "", id) to StationText.displayName("", "", id))
            val name = if (chinese) local else english
            ShortcutInfoCompat.Builder(context, StationShortcutPlan.shortcutId(id))
                .setShortLabel(name)
                .setLongLabel(name)
                .setIcon(icon)
                .setRank(index + 1)
                .setIntent(DeepLink.stationIntent(context, id, StationLinkSource.SHORTCUT))
                .addCapabilityBinding(OPEN_APP_FEATURE, FEATURE_PARAMETER, listOf(local, english).distinct())
                .build()
        }
        val shortcuts = listOf(airQuality) + stationShortcuts
        val current = ShortcutManagerCompat.getDynamicShortcuts(context)
            .sortedBy { it.rank }
            .map { it.id to it.shortLabel.toString() }
        if (current == shortcuts.map { it.id to it.shortLabel.toString() }) return
        if (!ShortcutManagerCompat.setDynamicShortcuts(context, shortcuts)) Log.i(TAG, "Shortcut update rate-limited")
    }

    /** [id] in English and Traditional Chinese, for Assistant to match either. */
    private fun bothLanguages(context: Context, @StringRes id: Int): List<String> = listOf("en", "zh-TW").map { tag ->
        val configuration = Configuration(context.resources.configuration)
        configuration.setLocales(LocaleList.forLanguageTags(tag))
        context.createConfigurationContext(configuration).getString(id)
    }.distinct()
}
