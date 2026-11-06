package com.kfpun.twaqi.ads

import android.util.Log
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.google.android.gms.ads.AdListener
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import com.google.android.gms.ads.LoadAdError
import com.kfpun.twaqi.R
import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.pro.ProGraph
import com.kfpun.twaqi.pro.ProNavigation
import com.kfpun.twaqi.pro.ProScreenSource

/**
 * An AdMob banner along the bottom of a screen (iOS `AdBannerView`), with a
 * "Remove ads" link to Pro. Takes no space at all for Pro, or until consent
 * allows ads ([AdsPolicy]).
 */
@Composable
fun AdBanner(placement: AdPlacement, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val repository = remember(context) { ProGraph.repository(context) }
    val entitlement by repository.entitlement.collectAsStateWithLifecycle()
    val canRequestAds by AdConsent.canRequestAds.collectAsStateWithLifecycle()
    if (!AdsPolicy.showBanner(entitlement, canRequestAds)) return

    Column(modifier = modifier.fillMaxWidth(), horizontalAlignment = Alignment.End) {
        TextButton(
            onClick = { ProNavigation.open(context, ProScreenSource.AD_BANNER) },
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp),
            modifier = Modifier.height(32.dp)
        ) {
            Text(stringResource(R.string.ads_remove), style = MaterialTheme.typography.labelMedium)
        }
        // The standard 320x50 banner, centred, as on iOS (AdSizeBanner); FOX-61. The large
        // adaptive banner it replaced was often over 100dp tall on phones.
        Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            BannerView(placement, AdsPolicy.bannerSize)
        }
    }
}

@Composable
private fun BannerView(placement: AdPlacement, adSize: AdSize) {
    var adView by remember { mutableStateOf<AdView?>(null) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle, adView) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_PAUSE -> adView?.pause()
                Lifecycle.Event.ON_RESUME -> adView?.resume()
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    AndroidView(
        modifier = Modifier.width(adSize.width.dp).height(adSize.height.dp),
        factory = { viewContext ->
            AdView(viewContext).apply {
                setAdSize(adSize)
                adUnitId = placement.adUnitId
                adListener = object : AdListener() {
                    override fun onAdClicked() {
                        Analytics.logEvent(
                            viewContext,
                            Analytics.AD_BANNER_TAPPED,
                            mapOf("placement" to placement.analyticsName)
                        )
                    }

                    // Without this an ad that never arrives is silent: just empty space.
                    override fun onAdFailedToLoad(error: LoadAdError) {
                        Log.w("TWAQIAds", "Banner ${placement.analyticsName} failed: ${error.code} ${error.message}")
                    }
                }
                loadAd(AdRequest.Builder().build())
                adView = this
            }
        },
        onRelease = { it.destroy() }
    )
}
