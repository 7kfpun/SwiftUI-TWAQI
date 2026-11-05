package com.kfpun.twaqi.watch.complication

import android.app.Activity
import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material3.AppScaffold
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.ButtonDefaults
import androidx.wear.compose.material3.ListHeader
import androidx.wear.compose.material3.ScreenScaffold
import androidx.wear.compose.material3.Text
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceService
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.watch.R
import com.kfpun.twaqi.watch.WatchSurfaces
import com.kfpun.twaqi.watch.data.WatchLocale
import com.kfpun.twaqi.watch.data.WatchStore
import com.kfpun.twaqi.watch.ui.WatchTheme

/**
 * Sets up one complication: its index, then its style (iOS `SelectIndexIntent`; watchOS has no
 * editor, so iOS lists every combination in the picker instead). Every style but the free face is
 * marked Pro, so nobody meets the lock as a surprise.
 */
class ComplicationConfigActivity : ComponentActivity() {
    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(WatchLocale.wrap(newBase))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val id = intent.getIntExtra(ComplicationDataSourceService.EXTRA_CONFIG_COMPLICATION_ID, -1)
        setResult(Activity.RESULT_CANCELED)
        setContent {
            WatchTheme {
                AppScaffold {
                    ConfigScreen { index, style ->
                        if (id !=
                            -1
                        ) {
                            WatchStore.get(
                                this@ComplicationConfigActivity
                            ).setComplicationConfig(id, index.key, style.id)
                        }
                        WatchSurfaces.requestUpdate(this@ComplicationConfigActivity)
                        setResult(Activity.RESULT_OK)
                        finish()
                    }
                }
            }
        }
    }
}

@Composable
private fun ConfigScreen(onDone: (AirIndexType, ComplicationStyle) -> Unit) {
    var index by rememberSaveable { mutableStateOf<AirIndexType?>(null) }
    val listState = rememberScalingLazyListState()
    val chosen = index

    ScreenScaffold(scrollState = listState) { padding ->
        ScalingLazyColumn(state = listState, contentPadding = padding, modifier = Modifier.fillMaxSize()) {
            if (chosen == null) {
                item { ListHeader { Text(stringResource(R.string.watch_complication_index)) } }
                items(AirIndexType.entries) { type ->
                    Button(
                        onClick = { index = type },
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.filledTonalButtonColors()
                    ) { Text(type.label) }
                }
            } else {
                item { ListHeader { Text(stringResource(R.string.watch_complication_style)) } }
                items(ComplicationStyle.entries) { style ->
                    val title = styleTitle(style, chosen)
                    Button(
                        onClick = { onDone(chosen, style) },
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.filledTonalButtonColors()
                    ) { Text(if (style.isPro) stringResource(R.string.watch_widget_pro, title) else title) }
                }
            }
        }
    }
}

/** "AQI", "AQI (number only)", "AQI (face)", "AQI (status)", as iOS names them in the picker. */
@Composable
private fun styleTitle(style: ComplicationStyle, type: AirIndexType): String = when (style) {
    ComplicationStyle.LABELLED -> type.label
    ComplicationStyle.NUMBER_ONLY -> stringResource(R.string.watch_widget_short, type.label)
    ComplicationStyle.FACE -> stringResource(R.string.watch_widget_face, type.label)
    ComplicationStyle.STATUS -> stringResource(R.string.watch_widget_status, type.label)
}
