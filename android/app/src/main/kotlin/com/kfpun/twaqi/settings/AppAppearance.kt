package com.kfpun.twaqi.settings

import android.content.Context
import android.content.SharedPreferences
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.content.edit
import com.kfpun.twaqi.analytics.Analytics

/**
 * Light, dark, or following the phone, chosen under Help (iOS `AppAppearance`, FOX-43).
 *
 * [id] is what is stored and sent with `select_appearance`, the same values as iOS.
 * [nightMode] is the AppCompat night mode it applies.
 */
enum class AppAppearance(val id: String, val nightMode: Int) {
    /** Whatever Android is set to, changing with it. */
    SYSTEM("system", AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM),
    LIGHT("light", AppCompatDelegate.MODE_NIGHT_NO),
    DARK("dark", AppCompatDelegate.MODE_NIGHT_YES)
    ;

    companion object {
        /** The stored [id], or [SYSTEM] when nothing or something unknown is stored. */
        fun fromId(id: String?): AppAppearance = entries.firstOrNull { it.id == id } ?: SYSTEM
    }
}

/**
 * Saves and applies [AppAppearance]. It is applied as AppCompat's night mode, which sets the
 * `uiMode` of every activity: `values-night` resources, the system bar icons, and Compose's
 * `isSystemInDarkTheme()` all follow it, so every screen and the map style (FOX-54) do too.
 * AppCompat keeps the mode only for the process, so [applyStored] runs when the app process
 * starts (`TwaqiApplication`).
 */
object AppAppearanceStore {
    /** The same preferences file as the app language (FOX-56), backed up with it. */
    internal const val PREFS = "settings"

    /** Same key as iOS `AppAppearance.defaultsKey`. */
    internal const val KEY = "appAppearance"

    fun current(context: Context): AppAppearance = read(prefs(context))

    /** Saves and applies [appearance]; open activities are recreated in it. */
    fun set(context: Context, appearance: AppAppearance) {
        write(prefs(context), appearance)
        apply(appearance)
        Analytics.logEvent(context, Analytics.SELECT_APPEARANCE, mapOf("label" to appearance.id))
    }

    /** Applies the saved choice. Call before any activity is created. */
    fun applyStored(context: Context) = apply(current(context))

    internal fun read(prefs: SharedPreferences): AppAppearance = AppAppearance.fromId(prefs.getString(KEY, null))

    /** [AppAppearance.SYSTEM] removes the key, as on iOS. */
    internal fun write(prefs: SharedPreferences, appearance: AppAppearance) = prefs.edit {
        if (appearance == AppAppearance.SYSTEM) remove(KEY) else putString(KEY, appearance.id)
    }

    internal fun apply(appearance: AppAppearance) {
        if (AppCompatDelegate.getDefaultNightMode() != appearance.nightMode) {
            AppCompatDelegate.setDefaultNightMode(appearance.nightMode)
        }
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
