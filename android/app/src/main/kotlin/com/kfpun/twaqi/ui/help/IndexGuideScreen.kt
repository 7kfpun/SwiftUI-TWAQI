package com.kfpun.twaqi.ui.help

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.kfpun.twaqi.R
import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.locale.AppLocale

/**
 * What one index means, where it comes from and what to do about it, ending with the colour
 * bands the app scores it against (iOS `IndexGuideView`).
 */
@Composable
fun IndexGuideScreen(page: DefinitionPage, onBack: () -> Unit) {
    val context = LocalContext.current
    val uriHandler = LocalUriHandler.current
    LaunchedEffect(page) {
        Analytics.logEvent(context, Analytics.OPEN_DEFINITION_PAGE, mapOf("label" to page.key))
    }
    HelpPage(title = stringResource(page.title), onBack = onBack) { padding ->
        HelpList(padding) {
            page.sections.forEach { section ->
                item {
                    SectionHeader(stringResource(section.header))
                    GuideText(stringResource(section.body))
                }
            }
            item {
                SectionHeader(stringResource(R.string.guide_section_bands))
                val bands = page.bands
                bands.forEachIndexed { index, band ->
                    BandRow(page, band, isLast = index == bands.lastIndex)
                }
                SectionFooter(stringResource(R.string.guide_bands_footer))
            }
            item {
                Spacer(Modifier.size(16.dp))
                LinkRow(stringResource(R.string.guide_further_reading), onClick = {
                    uriHandler.openSafely(page.url(AppLocale.isChinese(context)))
                }, external = true)
                SectionFooter(stringResource(R.string.guide_sources_footer))
            }
        }
    }
}

@Composable
private fun BandRow(page: DefinitionPage, band: AirStatus.Band, isLast: Boolean) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Spacer(Modifier.size(10.dp).background(Color(0xFF000000 or band.status.color.toLong()), CircleShape))
            Spacer(Modifier.width(8.dp))
            Text(
                stringResource(band.status.label),
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.weight(1f)
            )
            Text(
                page.rangeText(band, isLast),
                style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = TABULAR_FIGURES),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.End
            )
        }
        // The AQI is what the health advice is keyed to.
        val guidance = band.status.generalPublicGuidance
        if (page == DefinitionPage.AQI && guidance != null) {
            Text(
                stringResource(guidance),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 18.dp, top = 2.dp)
            )
        }
    }
}

private const val TABULAR_FIGURES = "tnum"
