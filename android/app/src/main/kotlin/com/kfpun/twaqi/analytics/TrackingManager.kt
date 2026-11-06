package com.kfpun.twaqi.analytics

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import com.google.firebase.FirebaseApp
import com.google.firebase.analytics.FirebaseAnalytics
import com.google.firebase.crashlytics.FirebaseCrashlytics
import com.kfpun.twaqi.BuildConfig
import com.kfpun.twaqi.settings.InstallPreferences

/** Where the opt-out is kept. */
interface TrackingPreferences {
    var isExcluded: Boolean
}

/** Turns Analytics and Crashlytics collection on or off. */
fun interface CollectionSwitch {
    fun setEnabled(enabled: Boolean)
}

/**
 * Who reports to Analytics and Crashlytics (iOS `TrackingManager`).
 *
 * - Debug builds never report, except to DebugView when started with
 *   `--ez analytics_debug true` ([enableDebugView]).
 * - Release builds report unless this install opted out: tapping the version row in Help 7 times
 *   toggles the opt-out ([toggleExcluded]), so the developer's own phones stay out of the counts
 *   without a rebuild. The choice is per install and left out of backups.
 */
class TrackingManager(
    private val preferences: TrackingPreferences,
    private val collection: CollectionSwitch,
    private val isDebugBuild: Boolean = BuildConfig.DEBUG
) {
    private var debugView = false

    /** Whether this install opted out of analytics and crash reports. */
    val isExcluded: Boolean get() = preferences.isExcluded

    /** Whether events and crashes are sent right now. */
    @Volatile
    var isReporting: Boolean = false
        private set

    /** Call once at process start, before anything is logged. */
    fun applyAtLaunch() {
        apply()
    }

    /**
     * Debug builds started with `--ez analytics_debug true`: send events, for Firebase DebugView
     * (with `adb shell setprop debug.firebase.analytics.app com.kfpun.twaqi`). Never on an
     * opted-out install, and never in a release build. Returns whether it took effect.
     */
    fun enableDebugView(): Boolean {
        if (!isDebugBuild || isExcluded) return false
        debugView = true
        apply()
        return true
    }

    /** Saves the choice and stops or resumes Analytics and Crashlytics at once. */
    fun setExcluded(excluded: Boolean) {
        preferences.isExcluded = excluded
        apply()
    }

    /** Flips the opt-out; returns the new value. */
    fun toggleExcluded(): Boolean = (!isExcluded).also(::setExcluded)

    private fun apply() {
        val enabled = !isExcluded && (!isDebugBuild || debugView)
        isReporting = enabled
        collection.setEnabled(enabled)
    }

    companion object {
        /** The `MainActivity` extra that turns on [enableDebugView] in a debug build. */
        const val EXTRA_ANALYTICS_DEBUG = "analytics_debug"

        @Volatile
        private var instance: TrackingManager? = null

        fun get(context: Context): TrackingManager = instance ?: synchronized(this) {
            instance ?: context.applicationContext.let { app ->
                TrackingManager(
                    SharedTrackingPreferences(InstallPreferences.get(app)),
                    FirebaseCollectionSwitch(app)
                )
            }.also { instance = it }
        }
    }
}

/** Counts taps on the version row; every [tapsNeeded]th tap returns true (iOS: 7). */
class VersionTapCounter(private val tapsNeeded: Int = TAPS_TO_TOGGLE) {
    private var taps = 0

    fun tap(): Boolean {
        taps += 1
        if (taps < tapsNeeded) return false
        taps = 0
        return true
    }

    companion object {
        const val TAPS_TO_TOGGLE = 7
    }
}

private class SharedTrackingPreferences(private val preferences: SharedPreferences) : TrackingPreferences {
    override var isExcluded: Boolean
        get() = preferences.getBoolean(KEY_EXCLUDED, false)
        set(value) = preferences.edit { putBoolean(KEY_EXCLUDED, value) }

    private companion object {
        /** The iOS UserDefaults key. */
        const val KEY_EXCLUDED = "analyticsExcluded"
    }
}

/** Does nothing without Firebase (no `google-services.json`). */
private class FirebaseCollectionSwitch(private val context: Context) : CollectionSwitch {
    override fun setEnabled(enabled: Boolean) {
        if (FirebaseApp.getApps(context).isEmpty()) return
        FirebaseAnalytics.getInstance(context).setAnalyticsCollectionEnabled(enabled)
        FirebaseCrashlytics.getInstance().run {
            setCrashlyticsCollectionEnabled(enabled)
            // Crashes kept while off would otherwise go out once it is back on.
            if (!enabled) deleteUnsentReports()
        }
    }
}
