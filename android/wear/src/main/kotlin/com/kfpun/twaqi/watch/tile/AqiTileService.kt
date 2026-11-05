package com.kfpun.twaqi.watch.tile

import android.content.Context
import androidx.concurrent.futures.SuspendToFutureAdapter
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DimensionBuilders.degrees
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.DimensionBuilders.expand
import androidx.wear.protolayout.DimensionBuilders.sp
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.ListenableFuture
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirLevel
import com.kfpun.twaqi.watch.R
import com.kfpun.twaqi.watch.complication.ComplicationContent
import com.kfpun.twaqi.watch.complication.faceDrawable
import com.kfpun.twaqi.watch.complication.statusLabel
import com.kfpun.twaqi.watch.data.WatchLocale
import com.kfpun.twaqi.watch.data.WatchPro
import com.kfpun.twaqi.watch.data.WatchReading
import com.kfpun.twaqi.watch.data.WatchRepository
import com.kfpun.twaqi.watch.data.WatchStore
import com.kfpun.twaqi.watch.ui.WatchActivity

/**
 * The Taiwan Air tile (FOX-62; the Wear OS counterpart of the iOS Smart Stack widget): the AQI of
 * the station the app follows (the nearest, or one the reader chose), in its level colour, with
 * the phone app's face. Part of Pro, as the Help guide says; without it the tile shows a lock that
 * opens the paywall.
 */
class AqiTileService : TileService() {
    override fun onTileRequest(requestParams: RequestBuilders.TileRequest): ListenableFuture<TileBuilders.Tile> =
        SuspendToFutureAdapter.launchFuture {
            val store = WatchStore.get(this@AqiTileService)
            val state = when {
                !WatchPro.isUnlocked(store) -> TileState.Locked

                else -> WatchRepository.get(this@AqiTileService).followedReading()?.let(TileState::Reading)
                    ?: TileState.Empty
            }
            val context = WatchLocale.wrap(this@AqiTileService)
            TileBuilders.Tile.Builder()
                .setResourcesVersion(RESOURCES_VERSION)
                // Readings are published hourly; half that keeps the tile at most one publish behind.
                .setFreshnessIntervalMillis(FRESHNESS_MILLIS)
                .setTileTimeline(TimelineBuilders.Timeline.fromLayoutElement(layout(context, state)))
                .build()
        }

    override fun onTileResourcesRequest(
        requestParams: RequestBuilders.ResourcesRequest
    ): ListenableFuture<ResourceBuilders.Resources> = SuspendToFutureAdapter.launchFuture {
        ResourceBuilders.Resources.Builder().setVersion(RESOURCES_VERSION).apply {
            AirLevel.showAllCases.forEach { level ->
                faceDrawable(level)?.let { addIdToImageMapping(faceId(level), image(it)) }
            }
            addIdToImageMapping(LOCK_ID, image(R.drawable.ic_lock))
        }.build()
    }

    /** What the tile shows. */
    sealed interface TileState {
        data object Locked : TileState

        data object Empty : TileState

        data class Reading(val reading: WatchReading) : TileState
    }

    private fun layout(context: Context, state: TileState): LayoutElementBuilders.LayoutElement {
        val type = AirIndexType.AQI
        val content = LayoutElementBuilders.Column.Builder()
            .setWidth(expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
        var ring: LayoutElementBuilders.Arc? = null

        when (state) {
            TileState.Locked -> {
                content.addContent(imageElement(LOCK_ID, 28f))
                content.addContent(spacer(4f))
                content.addContent(text("${type.label} · ${ComplicationContent.PRO}", 16f, WHITE, bold = true))
                content.addContent(spacer(2f))
                content.addContent(text(context.getString(R.string.watch_pro_locked), 13f, SECONDARY, maxLines = 2))
            }

            TileState.Empty -> content.addContent(
                text(context.getString(R.string.watch_no_station), 14f, WHITE, maxLines = 3)
            )

            is TileState.Reading -> {
                val reading = state.reading
                val level = reading.level(type)
                val colour = OPAQUE or level.color
                content.addContent(text(reading.displayName(WatchLocale.isChinese(context)), 13f, SECONDARY))
                content.addContent(text(reading.formatted(type), 44f, colour, bold = true))
                val row = LayoutElementBuilders.Row.Builder().setVerticalAlignment(
                    LayoutElementBuilders.VERTICAL_ALIGN_CENTER
                )
                if (level.hasFaceImage) {
                    row.addContent(imageElement(faceId(level), 20f))
                    row.addContent(LayoutElementBuilders.Spacer.Builder().setWidth(dp(4f)).build())
                }
                row.addContent(text(context.getString(statusLabel(level)), 14f, colour, bold = true, maxLines = 2))
                content.addContent(row.build())
                content.addContent(spacer(2f))
                content.addContent(
                    text("${type.label} · ${WatchReading.hourMinute(reading.publishTime)}", 12f, SECONDARY)
                )
                // The ring fills by level, as the complication's (a band, not the raw number).
                ring = LayoutElementBuilders.Arc.Builder()
                    .setAnchorAngle(degrees(0f))
                    .setAnchorType(LayoutElementBuilders.ARC_ANCHOR_START)
                    .addContent(
                        LayoutElementBuilders.ArcLine.Builder()
                            .setLength(degrees(360f * ComplicationContent.bandProgress(level)))
                            .setThickness(dp(6f))
                            .setColor(argb(colour))
                            .build()
                    )
                    .build()
            }
        }

        val open = ModifiersBuilders.Clickable.Builder()
            .setId("open")
            .setOnClick(
                ActionBuilders.LaunchAction.Builder().setAndroidActivity(
                    ActionBuilders.AndroidActivity.Builder()
                        .setPackageName(context.packageName)
                        .setClassName(WatchActivity::class.java.name)
                        .addKeyToExtraMapping(
                            WatchActivity.EXTRA_PAYWALL,
                            ActionBuilders.AndroidBooleanExtra.Builder().setValue(state == TileState.Locked).build()
                        )
                        .build()
                ).build()
            )
            .build()

        return LayoutElementBuilders.Box.Builder()
            .setWidth(expand())
            .setHeight(expand())
            .setModifiers(ModifiersBuilders.Modifiers.Builder().setClickable(open).build())
            .apply { ring?.let(::addContent) }
            .addContent(
                LayoutElementBuilders.Box.Builder()
                    .setWidth(expand())
                    .setHeight(expand())
                    .setModifiers(
                        ModifiersBuilders.Modifiers.Builder()
                            .setPadding(ModifiersBuilders.Padding.Builder().setAll(dp(PADDING)).build())
                            .build()
                    )
                    .addContent(content.build())
                    .build()
            )
            .build()
    }

    private fun text(value: String, size: Float, colour: Int, bold: Boolean = false, maxLines: Int = 1) =
        LayoutElementBuilders.Text.Builder()
            .setText(value)
            .setMaxLines(maxLines)
            .setMultilineAlignment(LayoutElementBuilders.TEXT_ALIGN_CENTER)
            .setFontStyle(
                LayoutElementBuilders.FontStyle.Builder()
                    .setSize(sp(size))
                    .setColor(argb(colour))
                    .setWeight(
                        if (bold) LayoutElementBuilders.FONT_WEIGHT_BOLD else LayoutElementBuilders.FONT_WEIGHT_NORMAL
                    )
                    .build()
            )
            .build()

    private fun imageElement(id: String, size: Float) =
        LayoutElementBuilders.Image.Builder().setResourceId(id).setWidth(dp(size)).setHeight(dp(size)).build()

    private fun spacer(height: Float) = LayoutElementBuilders.Spacer.Builder().setHeight(dp(height)).build()

    private fun image(resource: Int) = ResourceBuilders.ImageResource.Builder()
        .setAndroidResourceByResId(
            ResourceBuilders.AndroidImageResourceByResId.Builder().setResourceId(resource).build()
        )
        .build()

    private companion object {
        const val RESOURCES_VERSION = "1"
        const val FRESHNESS_MILLIS = 30L * 60 * 1000
        const val LOCK_ID = "lock"
        const val PADDING = 22f
        const val OPAQUE = 0xFF000000.toInt()
        val WHITE = 0xFFFFFFFF.toInt()
        val SECONDARY = 0xFFBDC1C6.toInt()

        fun faceId(level: AirLevel) = "face_${level.key}"
    }
}
