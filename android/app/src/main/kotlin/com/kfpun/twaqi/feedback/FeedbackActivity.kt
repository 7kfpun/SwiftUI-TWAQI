package com.kfpun.twaqi.feedback

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import com.kfpun.twaqi.ui.help.FeedbackScreen
import com.kfpun.twaqi.ui.theme.TWAQITheme

/**
 * The feedback form over the screen that opened it; open it with [FeedbackNavigation].
 * AppCompatActivity, so the in-app language applies below Android 13 (FOX-56).
 */
class FeedbackActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val source = FeedbackSource.fromAnalyticsName(intent.getStringExtra(FeedbackNavigation.EXTRA_SOURCE))
        setContent {
            TWAQITheme {
                FeedbackScreen(source = source, onBack = ::finish)
            }
        }
    }
}
