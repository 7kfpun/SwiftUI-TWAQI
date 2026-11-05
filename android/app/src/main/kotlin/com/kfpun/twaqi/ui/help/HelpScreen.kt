package com.kfpun.twaqi.ui.help

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.kfpun.twaqi.BuildConfig
import com.kfpun.twaqi.R
import com.kfpun.twaqi.locale.AppLocale
import com.kfpun.twaqi.ui.settings.AppearanceRow
import com.kfpun.twaqi.ui.settings.LanguageRow

/**
 * The Help tab (iOS `HelpView`) and the pages it opens. The back stack is kept as routes, so it
 * survives rotation and a language or appearance change, which restart the activity.
 *
 * @param isPro hides the Premium section; from the Pro entitlement (FOX-58).
 * @param onOpenPro opens the Pro screen (FOX-58).
 */
@Composable
fun HelpHost(isPro: Boolean, onOpenPro: () -> Unit, modifier: Modifier = Modifier) {
    var stack by rememberSaveable { mutableStateOf(emptyList<String>()) }
    val top = stack.lastOrNull()?.let(HelpDestination::fromRoute)
    val open: (HelpDestination) -> Unit = { stack = stack + it.route }
    val back: () -> Unit = { stack = stack.dropLast(1) }
    BackHandler(enabled = stack.isNotEmpty(), onBack = back)

    Box(modifier.fillMaxSize()) {
        when (top) {
            null -> HelpScreen(isPro = isPro, onOpenPro = onOpenPro, onOpen = open)
            is HelpDestination.IndexGuide -> IndexGuideScreen(top.page, onBack = back)
            HelpDestination.WidgetGuide -> WidgetGuideScreen(onBack = back)
            HelpDestination.WearOsGuide -> WearOsGuideScreen(onBack = back)
            HelpDestination.Cooperate -> CooperateScreen(onBack = back)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun HelpScreen(isPro: Boolean, onOpenPro: () -> Unit, onOpen: (HelpDestination) -> Unit) {
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(title = { Text(stringResource(R.string.help_help)) }, scrollBehavior = scrollBehavior)
        }
    ) { padding ->
        HelpList(padding) {
            HelpSection.order(isPro).forEach { section ->
                section(section, onOpenPro, onOpen)
            }
        }
    }
}

private fun LazyListScope.section(section: HelpSection, onOpenPro: () -> Unit, onOpen: (HelpDestination) -> Unit) {
    when (section) {
        HelpSection.PURCHASE -> item(key = "purchase") {
            SectionHeader(stringResource(R.string.help_in_app_purchase))
            LinkRow(stringResource(R.string.help_ad_free), onClick = onOpenPro, emphasized = true)
        }

        HelpSection.LANGUAGE -> item(key = "language") {
            SectionHeader(stringResource(R.string.help_language))
            LanguageRow()
            SectionFooter(stringResource(R.string.help_language_footer))
        }

        HelpSection.APPEARANCE -> item(key = "appearance") {
            SectionHeader(stringResource(R.string.help_appearance))
            AppearanceRow()
        }

        HelpSection.CONTACT -> item(key = "contact") {
            SectionHeader(stringResource(R.string.help_contact_us))
            LinkRow(stringResource(R.string.help_interested_to_be_our_business_partner), onClick = {
                onOpen(HelpDestination.Cooperate)
            })
        }

        HelpSection.WIDGETS_AND_WATCH -> item(key = "widgets") {
            SectionHeader(stringResource(R.string.help_widgets_and_watch))
            LinkRow(stringResource(R.string.help_widgets_title), onClick = { onOpen(HelpDestination.WidgetGuide) })
            LinkRow(stringResource(R.string.help_watch_title), onClick = { onOpen(HelpDestination.WearOsGuide) })
        }

        HelpSection.DEFINITION -> {
            item(key = "definition") { SectionHeader(stringResource(R.string.help_definition)) }
            DefinitionPage.entries.forEach { page ->
                item(key = "definition-${page.key}") {
                    LinkRow(stringResource(page.title), onClick = { onOpen(HelpDestination.IndexGuide(page)) })
                }
            }
        }

        HelpSection.ABOUT -> item(key = "about") { AboutSection() }
    }
}

/** Version, the privacy policy and terms, and the data source (all data-source mentions live in Help). */
@Composable
private fun AboutSection() {
    val context = LocalContext.current
    val uriHandler = LocalUriHandler.current
    val chinese = AppLocale.isChinese(context)
    // No header, as on iOS; the version label is unlocalised there too.
    Spacer(Modifier.height(16.dp))
    ValueRow("Version", "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
    LinkRow(stringResource(R.string.pro_privacy_policy), onClick = {
        uriHandler.openSafely(LegalPage.PRIVACY.url(chinese))
    }, external = true)
    LinkRow(stringResource(R.string.pro_terms_of_use), onClick = {
        uriHandler.openSafely(LegalPage.TERMS.url(chinese))
    }, external = true)
    SectionFooter(stringResource(R.string.help_data_provided_by_government))
}

/** The legal pages on the public website, in the app's language (iOS `ProView.legalURL`). */
enum class LegalPage(private val page: String) {
    PRIVACY("privacy.html"),
    TERMS("terms.html")
    ;

    fun url(chinese: Boolean): String = "https://taiwanair.wahthefox.com/" + (if (chinese) "zh-Hant/" else "") + page
}
