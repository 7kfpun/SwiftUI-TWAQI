package com.kfpun.twaqi.pro

import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.kfpun.twaqi.R
import com.kfpun.twaqi.ui.theme.TWAQITheme
import java.util.Locale

/** iOS `AirStatuses.good`, the Pro accent on both platforms. */
private val ProGreen = Color(0xFF009866)

/** Only what Pro adds, in the iOS order (`ProFeature`). */
internal enum class ProFeature(@DrawableRes val icon: Int, @StringRes val title: Int, @StringRes val detail: Int) {
    NO_ADS(R.drawable.ic_pro_ad_off, R.string.pro_feature_no_ads, R.string.pro_feature_no_ads_detail),
    COMPLICATIONS(
        R.drawable.ic_pro_watch,
        R.string.pro_feature_complications,
        R.string.pro_feature_complications_detail
    ),
    WIDGETS(
        R.drawable.ic_pro_widgets,
        R.string.pro_feature_widgets_android,
        R.string.pro_feature_widgets_android_detail
    ),
    SUPPORT(R.drawable.ic_pro_favorite, R.string.pro_feature_support, R.string.pro_feature_support_detail)
}

/**
 * What Pro includes, then the plans (iOS `ProView`): features first, since a list
 * of prices with nothing above it doesn't say what the money buys.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProScreen(
    state: ProUiState,
    entitlement: Entitlement?,
    onClose: () -> Unit,
    onBuy: (PlanOffer) -> Unit,
    onRetry: () -> Unit,
    onRestore: () -> Unit,
    onDismissDialog: () -> Unit,
    modifier: Modifier = Modifier
) {
    Scaffold(
        modifier = modifier.fillMaxSize(),
        containerColor = MaterialTheme.colorScheme.surfaceContainer,
        topBar = {
            TopAppBar(
                title = {},
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(
                            painterResource(R.drawable.ic_pro_close),
                            contentDescription = stringResource(R.string.pro_close)
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = 16.dp,
                end = 16.dp,
                top = padding.calculateTopPadding(),
                bottom = padding.calculateBottomPadding() + 24.dp
            ),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            item { Header() }

            item { SectionTitle(R.string.pro_features) }
            item {
                Group {
                    ProFeature.entries.forEachIndexed { index, feature ->
                        if (index > 0) RowDivider()
                        FeatureRow(feature)
                    }
                }
            }

            item { SectionTitle(R.string.pro_choose_plan) }
            item {
                Group {
                    Plans(state, onBuy, onRetry)
                }
            }
            if (entitlement == Entitlement.PENDING) {
                item { Footnote(stringResource(R.string.pro_purchase_pending)) }
            }
            item { Terms() }

            item {
                Group {
                    TextButton(
                        onClick = onRestore,
                        enabled = !state.busy,
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp)
                    ) {
                        Text(stringResource(R.string.help_restore_purchase), modifier = Modifier.fillMaxWidth())
                    }
                }
            }
        }
    }

    state.dialog?.let { dialog ->
        AlertDialog(
            onDismissRequest = onDismissDialog,
            confirmButton = { TextButton(onClick = onDismissDialog) { Text(stringResource(android.R.string.ok)) } },
            text = {
                Text(
                    stringResource(
                        when (dialog) {
                            ProDialog.PURCHASE_FAILED -> R.string.pro_purchase_failed
                            ProDialog.PURCHASE_PENDING -> R.string.pro_purchase_pending
                        }
                    )
                )
            }
        )
    }
}

@Composable
private fun Header() {
    Column(
        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Icon(
            painterResource(R.drawable.ic_pro_auto_awesome),
            contentDescription = null,
            tint = ProGreen,
            modifier = Modifier.size(48.dp)
        )
        Text(
            stringResource(R.string.pro_title),
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold
        )
        Text(
            stringResource(R.string.pro_subtitle),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun SectionTitle(@StringRes title: Int) {
    Text(
        stringResource(title),
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = 16.dp, top = 12.dp)
    )
}

@Composable
private fun Group(content: @Composable () -> Unit) {
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceContainerLowest,
        modifier = Modifier.fillMaxWidth()
    ) {
        Column { content() }
    }
}

@Composable
private fun RowDivider() {
    HorizontalDivider(modifier = Modifier.padding(start = 16.dp), color = MaterialTheme.colorScheme.outlineVariant)
}

@Composable
private fun FeatureRow(feature: ProFeature) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.Top
    ) {
        Icon(
            painterResource(feature.icon),
            contentDescription = null,
            tint = ProGreen,
            modifier = Modifier.size(28.dp)
        )
        Spacer(Modifier.width(12.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(feature.title), style = MaterialTheme.typography.titleMedium)
            Text(
                stringResource(feature.detail),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun Plans(state: ProUiState, onBuy: (PlanOffer) -> Unit, onRetry: () -> Unit) {
    if (state.offers.isEmpty()) {
        Box(modifier = Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
            if (state.loadFailed) {
                TextButton(onClick = onRetry) { Text(stringResource(R.string.pro_retry)) }
            } else {
                CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
            }
        }
        return
    }
    state.offers.forEachIndexed { index, offer ->
        if (index > 0) RowDivider()
        PlanRow(
            offer = offer,
            isPurchasing = state.purchasingPlan == offer.plan,
            enabled = !state.busy,
            onClick = { onBuy(offer) }
        )
    }
}

@Composable
private fun PlanRow(offer: PlanOffer, isPurchasing: Boolean, enabled: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(stringResource(offer.plan.nameRes), style = MaterialTheme.typography.titleMedium)
                if (offer.plan.isBestValue) BestValueBadge()
            }
            Text(
                if (offer.plan.months > 1) {
                    stringResource(
                        R.string.pro_per_month,
                        ProPricing.perMonth(offer.priceMicros, offer.plan.months, offer.currencyCode)
                    )
                } else {
                    stringResource(R.string.pro_billed_monthly)
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        if (isPurchasing) {
            CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
        } else {
            Text(offer.formattedPrice, style = MaterialTheme.typography.titleMedium)
        }
    }
}

internal val ProPlan.nameRes: Int
    get() = when (this) {
        ProPlan.ONE_MONTH -> R.string.pro_plan_1m
        ProPlan.SIX_MONTHS -> R.string.pro_plan_6m
        ProPlan.TWELVE_MONTHS -> R.string.pro_plan_12m
    }

@Composable
private fun BestValueBadge() {
    Text(
        stringResource(R.string.pro_best_value),
        style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.SemiBold,
        color = Color.White,
        modifier = Modifier
            .background(ProGreen, RoundedCornerShape(50))
            .padding(horizontal = 6.dp, vertical = 2.dp)
    )
}

@Composable
private fun Footnote(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 16.dp)
    )
}

/** The renewal terms and both legal links beside the offer, as on iOS. */
@Composable
private fun Terms() {
    val uriHandler = LocalUriHandler.current
    Column {
        Footnote(stringResource(R.string.pro_renewal_terms))
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp), modifier = Modifier.padding(start = 16.dp)) {
            LegalLink(R.string.pro_terms_of_use) { uriHandler.openUri(legalUrl("terms.html")) }
            LegalLink(R.string.pro_privacy_policy) { uriHandler.openUri(legalUrl("privacy.html")) }
        }
    }
}

@Composable
private fun LegalLink(@StringRes label: Int, onClick: () -> Unit) {
    Text(
        stringResource(label),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.clickable(onClick = onClick).padding(vertical = 8.dp)
    )
}

/** The public site's legal pages, in Chinese when the app is (iOS `ProView.legalURL`). */
internal fun legalUrl(page: String, locale: Locale = Locale.getDefault()): String {
    val prefix = if (locale.language == "zh") "zh-Hant/" else ""
    return "https://taiwanair.wahthefox.com/$prefix$page"
}

@Preview(showBackground = true, heightDp = 1100)
@Composable
private fun ProScreenPreview() {
    TWAQITheme {
        ProScreen(
            state = ProUiState(
                offers = ProPlan.entries.map {
                    PlanOffer(
                        it,
                        ProProducts.SUBSCRIPTION_ID,
                        "",
                        "NT$${it.months * 70}.00",
                        it.months * 70_000_000L,
                        "TWD"
                    )
                }
            ),
            entitlement = Entitlement.FREE,
            onClose = {},
            onBuy = {},
            onRetry = {},
            onRestore = {},
            onDismissDialog = {}
        )
    }
}
