package com.kfpun.twaqi

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
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
import com.kfpun.twaqi.ui.theme.TWAQITheme
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        startPro()
        setContent {
            TWAQITheme {
                HomeScreen()
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
 * Placeholder home screen; the map, list and details come with FOX-53 and later.
 * The Pro row and banner sit here until Help / settings and the real screens exist.
 */
@Composable
fun HomeScreen(modifier: Modifier = Modifier) {
    Scaffold(
        modifier = modifier.fillMaxSize(),
        bottomBar = { AdBanner(AdPlacement.MAIN, modifier = Modifier.navigationBarsPadding()) }
    ) { innerPadding ->
        Column(modifier = Modifier.fillMaxSize().padding(innerPadding)) {
            Box(modifier = Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                Text(
                    text = stringResource(R.string.app_name),
                    style = MaterialTheme.typography.headlineMedium,
                    color = MaterialTheme.colorScheme.primary
                )
            }
            ProSettingsRow()
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
