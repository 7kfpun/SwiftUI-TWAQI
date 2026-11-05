package com.kfpun.twaqi.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

/**
 * Debug builds only: asks the launcher to pin a widget (`--es widget air` or `detail`), so a
 * widget can be placed from adb for screenshots. The launcher then shows its own confirmation.
 */
class WidgetPinDebugActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val receiver = when (intent.getStringExtra("widget")) {
            "detail" -> StationDetailWidgetReceiver::class.java
            else -> AirQualityWidgetReceiver::class.java
        }
        val manager = getSystemService(AppWidgetManager::class.java)
        if (manager?.isRequestPinAppWidgetSupported == true) {
            manager.requestPinAppWidget(ComponentName(this, receiver), null, null)
        }
        finish()
    }
}
