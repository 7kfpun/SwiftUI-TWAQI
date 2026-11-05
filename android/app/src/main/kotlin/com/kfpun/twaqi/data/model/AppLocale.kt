package com.kfpun.twaqi.data.model

import java.util.Locale

/**
 * iOS `Locale.isChinese`: names, areas and counties come in both languages and the reader's
 * language picks one. On Android the per-app language (Settings, or the app's own picker later)
 * becomes the process default locale, so [Locale.getDefault] is the app language.
 */
object AppLocale {
    fun isChinese(locale: Locale = Locale.getDefault()): Boolean = locale.language.startsWith("zh")
}
