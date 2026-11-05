package com.kfpun.twaqi.ui.station

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import androidx.core.net.toUri
import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.ui.help.DefinitionPage

/**
 * The Wikipedia article for each index, in the reader's language (iOS `DefinitionPages.url`).
 * The station page's ⓘ opens it; it can point at the in-app index guide (FOX-97) instead.
 */
object DefinitionLinks {
    /** The article iOS `DefinitionPages.url` links to; one list, kept by the index guide (FOX-97). */
    fun url(type: AirIndexType, chinese: Boolean): String =
        DefinitionPage.entries.first { it.type == type }.url(chinese)

    /** Opens the page in the browser and logs `open_definition_page` with the index, as iOS does. */
    fun open(context: Context, type: AirIndexType, chinese: Boolean) {
        Analytics.logEvent(context, Analytics.OPEN_DEFINITION_PAGE, mapOf("label" to type.key))
        val intent = Intent(Intent.ACTION_VIEW, url(type, chinese).toUri())
        try {
            context.startActivity(intent)
        } catch (e: ActivityNotFoundException) {
            // No browser: nothing to open it in.
        }
    }
}
