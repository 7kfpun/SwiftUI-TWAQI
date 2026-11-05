package com.kfpun.twaqi.translation

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.State
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.kfpun.twaqi.TwaqiApplication
import com.kfpun.twaqi.locale.AppLocale

/** The app's [OnDeviceTranslation]; null where there is no app container (previews). */
private fun Context.onDeviceTranslation(): OnDeviceTranslation? =
    (applicationContext as? TwaqiApplication)?.container?.translation

/**
 * The translations a screen shows, in the app language: [display] gives the cached translation of
 * a Chinese API text, else the text as written. Reading it subscribes the caller, so it redraws
 * when a translation lands.
 */
@Stable
class ShownTranslations internal constructor(val target: String?, private val entries: State<Map<String, String>>) {
    private val cached: (String, String) -> String? = { text, target ->
        entries.value[OnDeviceTranslation.key(text, target)]
    }

    fun display(text: String): String = OnDeviceTranslation.display(text, target, cached)

    /** MOENV's forecast text: the Worker's translation, else on device, else as written. */
    fun forecastText(content: String, workerTranslation: String?): String =
        OnDeviceTranslation.forecastText(content, workerTranslation, target, cached)
}

@Composable
fun rememberShownTranslations(): ShownTranslations {
    val context = LocalContext.current
    val target = OnDeviceTranslation.target(AppLocale.isChinese(context))
    val service = remember(context) { context.onDeviceTranslation() }
    val entries = service?.translations?.collectAsState() ?: remember { mutableStateOf(emptyMap()) }
    return remember(target, entries) { ShownTranslations(target, entries) }
}

/**
 * Translates [texts] in the background (iOS `translatesOnDevice`); a caller reading
 * [rememberShownTranslations] redraws once they land. Does nothing in a Chinese UI or for texts
 * without Chinese in them.
 */
@Composable
fun TranslatesOnDevice(texts: List<String>) {
    val context = LocalContext.current
    val target = OnDeviceTranslation.target(AppLocale.isChinese(context))
    val worth = remember(texts) { OnDeviceTranslation.translatable(texts) }
    if (target == null || worth.isEmpty()) return
    LaunchedEffect(worth, target) {
        context.onDeviceTranslation()?.translate(worth, target)
    }
}
