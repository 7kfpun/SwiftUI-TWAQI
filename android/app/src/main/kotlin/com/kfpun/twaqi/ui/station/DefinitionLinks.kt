package com.kfpun.twaqi.ui.station

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import androidx.core.net.toUri
import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.data.model.AirIndexType
import java.net.URLEncoder

/**
 * The Wikipedia article for each index, in the reader's language (iOS `DefinitionPages.url`).
 * The station page opens it until the in-app index guide (FOX-97) takes over.
 */
object DefinitionLinks {
    fun url(type: AirIndexType, chinese: Boolean): String {
        val article = if (chinese) {
            when (type) {
                AirIndexType.AQI -> "空氣品質指標"
                AirIndexType.PM25 -> "細懸浮微粒"
                AirIndexType.PM10 -> "懸浮粒子"
                AirIndexType.O3 -> "臭氧"
                AirIndexType.CO -> "一氧化碳"
                AirIndexType.SO2 -> "二氧化硫"
                AirIndexType.NO2 -> "二氧化氮"
            }
        } else {
            when (type) {
                AirIndexType.AQI -> "Air_quality_index"
                AirIndexType.PM25, AirIndexType.PM10 -> "Particulates"
                AirIndexType.O3 -> "Tropospheric_ozone"
                AirIndexType.CO -> "Carbon_monoxide"
                AirIndexType.SO2 -> "Sulfur_dioxide"
                AirIndexType.NO2 -> "Nitrogen_dioxide"
            }
        }
        val host = if (chinese) "zh.wikipedia.org" else "en.wikipedia.org"
        val path = URLEncoder.encode(article, "UTF-8").replace("+", "%20")
        return "https://$host/wiki/$path"
    }

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
