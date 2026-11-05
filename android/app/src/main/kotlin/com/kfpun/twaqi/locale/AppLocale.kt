package com.kfpun.twaqi.locale

import android.app.LocaleManager
import android.content.Context
import android.content.res.Configuration
import android.content.res.Resources
import android.os.Build
import android.os.LocaleList
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.content.edit
import androidx.core.os.LocaleListCompat
import com.kfpun.twaqi.analytics.Analytics
import java.util.Locale

/**
 * The app's language, for every place text is produced.
 *
 * Android 13+ keeps the choice as the per-app locale (`LocaleManager`, also editable in the
 * phone's Settings › Apps › Taiwan Air › Language) and applies it to the whole process.
 * Older versions get it from `AppCompatDelegate.setApplicationLocales`, which applies it only
 * to AppCompat activities. Widgets (FOX-59), notifications (FOX-57) and workers run without
 * one, so they must build their text from [localizedContext], or they fall back to the phone
 * language, the iOS widget bug FOX-42.
 */
object AppLocale {
    internal const val PREFS = "settings"

    /** Same key as iOS `AppLanguage.defaultsKey`. */
    internal const val KEY = "appLanguage"

    /** The language chosen in the app, or [AppLanguage.SYSTEM]. Safe to call from any process component. */
    fun current(context: Context): AppLanguage {
        val platformTags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.getSystemService(LocaleManager::class.java)?.applicationLocales?.toLanguageTags()
        } else {
            null
        }
        return resolve(Build.VERSION.SDK_INT, platformTags, prefs(context).getString(KEY, null))
    }

    /**
     * On Android 13+ the system's per-app locale wins, since it can be changed outside the app.
     * Older versions have only the choice stored here. (AppCompat's own record is read only when
     * an activity starts, so a widget or notification in a cold process would not see it.)
     */
    internal fun resolve(sdk: Int, platformTags: String?, storedId: String?): AppLanguage =
        if (sdk >= Build.VERSION_CODES.TIRAMISU) {
            AppLanguage.fromLocaleTag(platformTags?.substringBefore(',')?.takeIf { it.isNotBlank() })
        } else {
            AppLanguage.fromId(storedId)
        }

    /** Saves and applies [language]; open activities are recreated in it. */
    fun set(context: Context, language: AppLanguage) {
        prefs(context).edit {
            if (language.localeTag == null) remove(KEY) else putString(KEY, language.id)
        }
        AppCompatDelegate.setApplicationLocales(localeList(language))
        Analytics.logEvent(context, Analytics.SELECT_LANGUAGE, mapOf("label" to language.id))
    }

    internal fun localeList(language: AppLanguage): LocaleListCompat =
        language.localeTag?.let(LocaleListCompat::forLanguageTags) ?: LocaleListCompat.getEmptyLocaleList()

    /** The locale the app shows: the choice, else the phone's. Use it for dates and numbers too. */
    fun locale(context: Context): Locale = current(context).localeTag?.let(Locale::forLanguageTag) ?: systemLocale()

    fun isChinese(context: Context): Boolean = locale(context).language == "zh"

    /**
     * [context] with its resources in the app's language: `localizedContext(context).getString(…)`.
     * Use it wherever there is no activity: widgets, notifications and their channels, workers.
     */
    fun localizedContext(context: Context): Context {
        val tag = current(context).localeTag ?: return context
        val configuration = Configuration(context.resources.configuration)
        configuration.setLocales(LocaleList.forLanguageTags(tag))
        return context.createConfigurationContext(configuration)
    }

    private fun systemLocale(): Locale = Resources.getSystem().configuration.locales[0]

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
