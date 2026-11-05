package com.kfpun.twaqi.ui.navigation

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.net.toUri
import com.kfpun.twaqi.MainActivity
import com.kfpun.twaqi.pro.ProDeepLink
import com.kfpun.twaqi.pro.ProNavigation
import com.kfpun.twaqi.pro.ProScreenSource

/** Where a station link came from (iOS `StationLinkSource`). */
enum class StationLinkSource(val analyticsName: String) {
    /** A tap on a medium, large or station detail widget, on the station it shows (FOX-59). */
    WIDGET("widget"),

    /** The Quick Settings tile (FOX-95), Android's Control Center control. */
    TILE("tile"),

    /**
     * A station's launcher shortcut or Google Assistant opening it (FOX-95), as iOS logs its "Open
     * station" App Shortcut.
     */
    SHORTCUT("shortcut"),

    /** `twaqi://station` with no `source`, or one this build doesn't know. */
    DEEP_LINK("deep_link")
    ;

    companion object {
        fun fromAnalyticsName(name: String?): StationLinkSource =
            entries.firstOrNull { it.analyticsName == name } ?: DEEP_LINK
    }
}

/**
 * The app's one deep-link router (iOS `DeepLink`): `twaqi://pro?source=…`,
 * `twaqi://station?id=…&source=…` and `twaqi://air-quality[?id=…]`. Widgets, the launcher
 * shortcuts, Google Assistant and the Quick Settings tile (FOX-95) build their links here. Parsing
 * is pure, from the URI's parts, so it is unit tested without Android.
 */
sealed interface DeepLink {
    data class Pro(val source: ProScreenSource) : DeepLink

    data class Station(val stationId: Int, val source: StationLinkSource) : DeepLink

    /**
     * "What's the air?" (FOX-95, iOS `GetAirQualityIntent`): the answer card for [stationId], or
     * for the nearest station when it is null. The "Air quality" launcher shortcut and Assistant
     * open it.
     */
    data class AirQuality(val stationId: Int?) : DeepLink

    companion object {
        const val SCHEME = ProDeepLink.SCHEME
        const val STATION_HOST = "station"
        const val AIR_QUALITY_HOST = "air-quality"
        const val ID_PARAMETER = "id"
        const val SOURCE_PARAMETER = "source"

        /** Null for any URI that isn't one of ours. */
        fun parse(scheme: String?, host: String?, path: String?, query: (String) -> String?): DeepLink? {
            ProDeepLink.source(scheme, host, path, query(ProDeepLink.SOURCE_PARAMETER))?.let { return Pro(it) }
            if (!scheme.equals(SCHEME, ignoreCase = true)) return null
            if (!path.isNullOrEmpty() && path.trim('/').isNotEmpty()) return null
            val id = query(ID_PARAMETER)
            return when {
                host.equals(STATION_HOST, ignoreCase = true) -> {
                    val stationId = id?.toIntOrNull()?.takeIf { it > 0 } ?: return null
                    Station(stationId, StationLinkSource.fromAnalyticsName(query(SOURCE_PARAMETER)))
                }

                // No id is the nearest station; an id that isn't one is not ours.
                host.equals(AIR_QUALITY_HOST, ignoreCase = true) ->
                    if (id.isNullOrEmpty()) {
                        AirQuality(null)
                    } else {
                        AirQuality(id.toIntOrNull()?.takeIf { it > 0 } ?: return null)
                    }

                else -> null
            }
        }

        fun parse(uri: Uri?): DeepLink? = uri?.let {
            parse(it.scheme, it.host, it.path) { name -> it.getQueryParameter(name) }
        }

        /**
         * What the app should open, or null to ignore it: the Pro screen for someone who already
         * has Pro, and a station the app doesn't know. Any app or web page can open the scheme, so
         * `twaqi://station?id=999999` must not open a page for a station that isn't there.
         */
        fun route(link: DeepLink?, isPro: Boolean, isKnownStation: (Int) -> Boolean): DeepLink? = when (link) {
            null -> null
            is Pro -> link.takeUnless { isPro }
            is Station -> link.takeIf { isKnownStation(it.stationId) }
            is AirQuality -> link.takeIf { it.stationId == null || isKnownStation(it.stationId) }
        }

        /** `twaqi://station?id=…&source=…` */
        fun stationUri(stationId: Int, source: StationLinkSource): String =
            "$SCHEME://$STATION_HOST?$ID_PARAMETER=$stationId&$SOURCE_PARAMETER=${source.analyticsName}"

        /** `twaqi://air-quality`, or `twaqi://air-quality?id=…` for one station. */
        fun airQualityUri(stationId: Int? = null): String =
            "$SCHEME://$AIR_QUALITY_HOST" + (stationId?.let { "?$ID_PARAMETER=$it" } ?: "")

        /** `twaqi://pro?source=…` */
        fun proUri(source: ProScreenSource): String =
            "$SCHEME://${ProDeepLink.HOST}?${ProDeepLink.SOURCE_PARAMETER}=${source.analyticsName}"

        /**
         * Opens the Pro screen, for a locked widget's tap. It carries its own [proUri], because
         * Glance gives an activity intent without data a `glance-action:` one, which the Pro screen
         * would read as a link it doesn't know and close.
         */
        fun proIntent(context: Context, source: ProScreenSource): Intent = ProNavigation.intent(context, source)
            .setAction(Intent.ACTION_VIEW)
            .setData(proUri(source).toUri())
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        /** Opens [stationId] in the app, for a widget's, a launcher shortcut's or the tile's tap. */
        fun stationIntent(context: Context, stationId: Int, source: StationLinkSource): Intent =
            Intent(Intent.ACTION_VIEW, stationUri(stationId, source).toUri(), context, MainActivity::class.java)
                .addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
    }
}
