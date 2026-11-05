package com.kfpun.twaqi

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.kfpun.twaqi.settings.AppAppearanceStore
import com.kfpun.twaqi.ui.MainTabs
import com.kfpun.twaqi.ui.theme.TWAQITheme

// AppCompatActivity, so AppCompatDelegate.setApplicationLocales applies the app language
// below Android 13 (FOX-56).
class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Help › Appearance (FOX-97), before the activity takes its configuration.
        AppAppearanceStore.applyStored(this)
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            TWAQITheme {
                HomeScreen()
            }
        }
    }
}

/**
 * The tabs (FOX-97: Help). The map, list and details come with FOX-54 and later.
 */
@Composable
fun HomeScreen(modifier: Modifier = Modifier) {
    // FOX-58: the Pro entitlement and `ProNavigation.open(context, ProScreenSource.HELP_ROW)`.
    MainTabs(isPro = false, onOpenPro = {}, modifier = modifier)
}

@Preview(showBackground = true)
@Composable
private fun HomeScreenPreview() {
    TWAQITheme {
        HomeScreen()
    }
}
