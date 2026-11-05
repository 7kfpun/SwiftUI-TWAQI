package com.kfpun.twaqi.watch.data

import android.content.Context
import android.content.res.Configuration
import android.os.LocaleList

/**
 * The watch's language (FOX-56): the phone app's choice when the phone has relayed one, else the
 * watch's own. Activities wrap their base context with [wrap]; the complication and tile build
 * their text from [wrap] too, since they run without an activity.
 */
object WatchLocale {
    /** The locale tag for a relayed `AppLanguage` id, or null to follow the watch. */
    fun localeTag(languageId: String): String? = when (languageId) {
        "zh-Hant" -> "zh-TW"
        "en" -> "en"
        else -> null
    }

    fun wrap(context: Context): Context {
        val tag = localeTag(WatchStore.get(context).languageId) ?: return context
        val configuration = Configuration(context.resources.configuration)
        configuration.setLocales(LocaleList.forLanguageTags(tag))
        return context.createConfigurationContext(configuration)
    }

    fun isChinese(context: Context): Boolean = context.resources.configuration.locales[0].language == "zh"
}
