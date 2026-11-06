package com.kfpun.twaqi.watch

import android.content.ComponentName
import android.content.Context
import androidx.wear.tiles.TileService
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import com.kfpun.twaqi.watch.complication.AqiComplicationService
import com.kfpun.twaqi.watch.tile.AqiTileService

/** Redraws the complication and the tile (iOS `WidgetCenter.reloadAllTimelines`). */
object WatchSurfaces {
    fun requestUpdate(context: Context) {
        runCatching {
            ComplicationDataSourceUpdateRequester
                .create(context, ComponentName(context, AqiComplicationService::class.java))
                .requestUpdateAll()
        }
        runCatching { TileService.getUpdater(context).requestUpdate(AqiTileService::class.java) }
    }
}
