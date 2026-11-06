package com.kfpun.twaqi.forms

import android.content.Context
import android.content.res.Resources
import android.os.Build
import com.kfpun.twaqi.BuildConfig
import com.kfpun.twaqi.locale.AppLocale
import java.util.TimeZone

/**
 * The app and device details sent with every Directus form, never shown to the user
 * (iOS `FeedbackSubmission.make` and `clientMeta`).
 *
 * @property locale the phone's locale, e.g. `en-TW` (iOS `Locale.current`).
 * @property appLanguage the language the app is shown in: `zh-Hant` or `en`.
 * @property preferredLanguages the phone's first three languages, comma-separated.
 */
data class ClientInfo(
    val packageName: String,
    val appVersion: String,
    val build: String,
    val deviceModel: String,
    val osVersion: String,
    val deviceIdiom: String,
    val locale: String,
    val appLanguage: String,
    val preferredLanguages: String,
    val timeZone: String
) {
    /**
     * `meta_json`. [anonymousId] adds a per-install id; the business partner form leaves it out,
     * since an enquiry carries contact details already.
     */
    fun meta(anonymousId: String? = null): Map<String, String> = buildMap {
        put("bundle_id", packageName)
        put("build", build)
        put("app_platform", APP_PLATFORM)
        put("device_idiom", deviceIdiom)
        put("app_language", appLanguage)
        put("preferred_languages", preferredLanguages)
        put("time_zone", timeZone)
        anonymousId?.let { put("anonymous_id", it) }
    }

    companion object {
        /** The Directus `platform` value for this app. */
        const val PLATFORM = "android"

        /** `meta_json.app_platform`: the OS this build runs on. */
        const val APP_PLATFORM = "android"

        fun current(context: Context): ClientInfo {
            // The phone's own languages: the app's choice (FOX-56) changes the process default.
            val systemLocales = Resources.getSystem().configuration.locales
            val tablet = context.resources.configuration.smallestScreenWidthDp >= TABLET_MIN_WIDTH_DP
            return ClientInfo(
                packageName = BuildConfig.APPLICATION_ID,
                appVersion = BuildConfig.VERSION_NAME,
                build = BuildConfig.VERSION_CODE.toString(),
                deviceModel = "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
                osVersion = Build.VERSION.RELEASE,
                deviceIdiom = if (tablet) "tablet" else "phone",
                locale = systemLocales[0].toLanguageTag(),
                appLanguage = if (AppLocale.isChinese(context)) "zh-Hant" else "en",
                preferredLanguages = (0 until minOf(systemLocales.size(), 3))
                    .joinToString(",") { systemLocales[it].toLanguageTag() },
                timeZone = TimeZone.getDefault().id
            )
        }

        private const val TABLET_MIN_WIDTH_DP = 600
    }
}
