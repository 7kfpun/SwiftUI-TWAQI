package com.kfpun.twaqi.widget

import android.content.Context
import androidx.glance.GlanceId
import androidx.glance.action.ActionParameters
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.state.updateAppWidgetState
import com.kfpun.twaqi.data.model.AirIndexType
import java.time.Instant

/**
 * The ‹ › buttons on a medium or large widget (iOS `ShowWidgetPageIntent`, FOX-76): stores the
 * station to show for this widget and redraws it from saved readings, so the page changes at once,
 * offline too. Then plans the return to the widget's own station 30 minutes on.
 */
class ShowWidgetPageAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        // -1 (or nothing): back to the widget's own station.
        val stationId = parameters[STATION_ID]?.takeIf { it > 0 }
        val pageIds = parameters[PAGE_IDS]?.split(',')?.mapNotNull { it.toIntOrNull() }.orEmpty()
        val now = Instant.now()
        var saved = WidgetPageState()
        updateAppWidgetState(context, glanceId) { prefs ->
            saved = WidgetPaging.paged(WidgetStateKeys.pageState(prefs), stationId, now)
            WidgetStateKeys.writePageState(prefs, saved)
            WidgetStateKeys.bumpVersion(prefs, now)
        }
        AirQualityWidget().update(context, glanceId)
        val appWidgetId = GlanceAppWidgetManager(context).getAppWidgetId(glanceId)
        WidgetUpdater.scheduleReset(context, appWidgetId, WidgetPaging.resetAt(saved, pageIds, now), now)
    }

    companion object {
        val STATION_ID = ActionParameters.Key<Int>("stationId")
        val PAGE_IDS = ActionParameters.Key<String>("pageIds")
    }
}

/** A tap on a widget's index label (iOS `CycleWidgetIndexIntent`): shows the next index for this widget. */
class CycleWidgetIndexAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val index = AirIndexType.fromKey(parameters[INDEX]) ?: return
        val now = Instant.now()
        updateAppWidgetState(context, glanceId) { prefs ->
            WidgetStateKeys.writePageState(prefs, WidgetPaging.cycled(WidgetStateKeys.pageState(prefs), index, now))
            WidgetStateKeys.bumpVersion(prefs, now)
        }
        AirQualityWidget().update(context, glanceId)
    }

    companion object {
        val INDEX = ActionParameters.Key<String>("index")
    }
}
