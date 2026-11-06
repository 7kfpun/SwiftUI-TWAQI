package com.kfpun.twaqi.locale

/**
 * The language chosen under Help, overriding the phone's for this app (iOS `AppLanguage`).
 *
 * [id] is what is stored and sent with `select_language`, the same values as iOS.
 * [localeTag] is the Android locale it applies (`values-zh-rTW`), or null to follow the phone.
 */
enum class AppLanguage(val id: String, val localeTag: String?) {
    /** Whatever Android gives the app. */
    SYSTEM("system", null),
    TRADITIONAL_CHINESE("zh-Hant", "zh-TW"),
    ENGLISH("en", "en")
    ;

    companion object {
        /** The stored [id], or [SYSTEM] when nothing or something unknown is stored. */
        fun fromId(id: String?): AppLanguage = entries.firstOrNull { it != SYSTEM && it.id == id } ?: SYSTEM

        /**
         * The language a per-app locale tag stands for: any Chinese is Traditional Chinese (the
         * only Chinese the app ships), any English is English, and nothing else is a choice.
         */
        fun fromLocaleTag(tag: String?): AppLanguage =
            when (tag?.substringBefore('-')?.substringBefore('_')?.lowercase()) {
                "zh" -> TRADITIONAL_CHINESE
                "en" -> ENGLISH
                else -> SYSTEM
            }
    }
}
