package com.kfpun.twaqi

import android.os.Bundle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.kfpun.twaqi.ads.AdBanner
import com.kfpun.twaqi.ads.AdConsent
import com.kfpun.twaqi.ads.AdPlacement
import com.kfpun.twaqi.pro.Entitlement
import com.kfpun.twaqi.pro.ProActivity
import com.kfpun.twaqi.pro.ProGraph
import com.kfpun.twaqi.pro.ProSettingsRow
import com.kfpun.twaqi.ui.debug.DataDebugScreen
import com.kfpun.twaqi.ui.favourites.FavouritesHost
import com.kfpun.twaqi.ui.settings.LanguageSection
import com.kfpun.twaqi.ui.theme.TWAQITheme
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

// AppCompatActivity, so AppCompatDelegate.setApplicationLocales applies the app language
// below Android 13 (FOX-56).
class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        startPro()
        setContent {
            TWAQITheme {
                // Debug builds can open the data-layer check screen (FOX-53) until the real
                // screens land; back returns home.
                var showDataScreen by rememberSaveable { mutableStateOf(false) }
                // Favourites (FOX-55) until the tab bar lands; back returns home.
                var showFavourites by rememberSaveable { mutableStateOf(false) }
                if (showDataScreen) {
                    BackHandler { showDataScreen = false }
                    DataDebugScreen()
                } else if (showFavourites) {
                    BackHandler { showFavourites = false }
                    FavouritesHost()
                } else {
                    HomeScreen(
                        onOpenDataScreen = if (BuildConfig.DEBUG) ({ showDataScreen = true }) else null,
                        onOpenFavourites = { showFavourites = true }
                    )
                }
            }
        }
    }

    /** FOX-58: re-check Pro with Play whenever the app comes to the front; ask for ad consent if free. */
    private fun startPro() {
        if (BuildConfig.DEBUG &&
            intent.getBooleanExtra(ProActivity.EXTRA_DEMO_BILLING, false)
        ) {
            ProGraph.useDemoBilling()
        }
        val pro = ProGraph.repository(this)
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) { pro.refresh() }
        }
        lifecycleScope.launch {
            // Pro users see no ads, so no consent form; one who lapses gets it then.
            pro.entitlement.filterNotNull().first { it != Entitlement.PRO }
            AdConsent.gather(this@MainActivity)
        }
    }
}

/**
 * Placeholder home screen; the map, list and details come with the later Android tickets. The
 * language picker and the Pro row sit here until the Help screen exists, and the banner until
 * the real screens do. [onOpenDataScreen] (debug builds only) adds a button to the data-layer
 * check screen, [onOpenFavourites] one to Favourites (FOX-55).
 */
@Composable
fun HomeScreen(
    modifier: Modifier = Modifier,
    onOpenDataScreen: (() -> Unit)? = null,
    onOpenFavourites: (() -> Unit)? = null
) {
    Scaffold(
        modifier = modifier.fillMaxSize(),
        bottomBar = { AdBanner(AdPlacement.MAIN, modifier = Modifier.navigationBarsPadding()) }
    ) { innerPadding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(innerPadding),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = stringResource(R.string.app_name),
                style = MaterialTheme.typography.headlineMedium,
                color = MaterialTheme.colorScheme.primary
            )
            LanguageSection(Modifier.fillMaxWidth().padding(top = 24.dp))
            ProSettingsRow(Modifier.padding(top = 8.dp))
            if (onOpenFavourites != null) {
                OutlinedButton(onClick = onOpenFavourites, modifier = Modifier.padding(top = 24.dp)) {
                    Text(stringResource(R.string.tabbar_favourites))
                }
            }
            if (onOpenDataScreen != null) {
                OutlinedButton(onClick = onOpenDataScreen, modifier = Modifier.padding(top = 24.dp)) {
                    Text(stringResource(R.string.debug_data_title))
                }
            }
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun HomeScreenPreview() {
    TWAQITheme {
        HomeScreen()
    }
}
