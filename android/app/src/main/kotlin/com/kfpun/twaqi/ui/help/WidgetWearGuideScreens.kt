package com.kfpun.twaqi.ui.help

import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.kfpun.twaqi.R
import com.kfpun.twaqi.analytics.Analytics

/** One guide section: a header, paragraphs, and an optional footer. */
private data class GuideSection(
    @param:StringRes val header: Int,
    val paragraphs: List<Int>,
    @param:StringRes val footer: Int? = null
)

/**
 * Home screen widgets (FOX-59): what they show, and how to add one. iOS `WidgetGuideView`,
 * reworded for Android: no Lock Screen, StandBy or widget stacks.
 */
@Composable
fun WidgetGuideScreen(onBack: () -> Unit) {
    GuideScreen(
        title = R.string.help_widgets_title,
        event = Analytics.OPEN_WIDGET_GUIDE,
        sections = listOf(
            GuideSection(R.string.help_widgets_shows_header, listOf(R.string.help_widgets_shows_body)),
            GuideSection(
                R.string.help_widgets_favourites_header,
                listOf(
                    R.string.help_widgets_favourites_body,
                    R.string.help_widgets_favourites_add,
                    R.string.help_widgets_favourites_offline
                )
            ),
            GuideSection(R.string.help_widgets_index_header, listOf(R.string.help_widgets_index_body)),
            GuideSection(
                R.string.help_widgets_paging_header,
                listOf(
                    R.string.help_widgets_paging_body,
                    R.string.help_widgets_cycle_body,
                    R.string.help_widgets_stack_tip
                )
            ),
            GuideSection(R.string.help_widgets_sizes_header, listOf(R.string.help_widgets_home_sizes)),
            GuideSection(
                R.string.help_widgets_add_header,
                listOf(R.string.help_widgets_add_1, R.string.help_widgets_add_2, R.string.help_widgets_add_3),
                footer = R.string.help_widgets_footer
            )
        ),
        onBack = onBack
    )
}

/**
 * The Wear OS app, complication and tile (FOX-62). iOS `WatchGuideView`, reworded for Wear OS:
 * a tile in place of the Smart Stack.
 */
@Composable
fun WearOsGuideScreen(onBack: () -> Unit) {
    GuideScreen(
        title = R.string.help_watch_title,
        event = Analytics.OPEN_WATCH_GUIDE,
        sections = listOf(
            GuideSection(R.string.help_watch_app_header, listOf(R.string.help_watch_app_body)),
            GuideSection(R.string.help_watch_complications_header, listOf(R.string.help_watch_complications_body)),
            GuideSection(R.string.help_watch_tile_header, listOf(R.string.help_watch_tile_body)),
            GuideSection(
                R.string.help_watch_add_header,
                listOf(R.string.help_watch_add_1, R.string.help_watch_add_2),
                footer = R.string.help_watch_footer
            )
        ),
        onBack = onBack
    )
}

/**
 * Launcher shortcuts, Google Assistant and the Quick Settings tile (FOX-95). iOS `ShortcutsGuideView`
 * (Siri, Shortcuts, Control Center), reworded for what Android has.
 */
@Composable
fun ShortcutsGuideScreen(onBack: () -> Unit) {
    GuideScreen(
        title = R.string.help_shortcuts_title,
        event = Analytics.OPEN_SHORTCUTS_GUIDE,
        sections = listOf(
            GuideSection(R.string.help_shortcuts_launcher_header, listOf(R.string.help_shortcuts_launcher_body)),
            GuideSection(
                R.string.help_shortcuts_assistant_header,
                listOf(R.string.help_shortcuts_assistant_body, R.string.help_shortcuts_location_body)
            ),
            GuideSection(
                R.string.help_shortcuts_tile_header,
                listOf(R.string.help_shortcuts_tile_body),
                footer = R.string.help_shortcuts_footer
            )
        ),
        onBack = onBack
    )
}

@Composable
private fun GuideScreen(@StringRes title: Int, event: String, sections: List<GuideSection>, onBack: () -> Unit) {
    val context = LocalContext.current
    LaunchedEffect(event) { Analytics.logEvent(context, event) }
    HelpPage(title = stringResource(title), onBack = onBack) { padding ->
        HelpList(padding) {
            sections.forEach { section ->
                item {
                    SectionHeader(stringResource(section.header))
                    section.paragraphs.forEach { GuideText(stringResource(it)) }
                    section.footer?.let { SectionFooter(stringResource(it)) }
                }
            }
        }
    }
}
