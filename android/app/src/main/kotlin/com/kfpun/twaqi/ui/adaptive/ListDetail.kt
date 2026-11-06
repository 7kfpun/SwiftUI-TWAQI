@file:OptIn(ExperimentalMaterial3AdaptiveApi::class)

package com.kfpun.twaqi.ui.adaptive

import androidx.annotation.DrawableRes
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.VerticalDivider
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.layout.AnimatedPane
import androidx.compose.material3.adaptive.layout.HingePolicy
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffold
import androidx.compose.material3.adaptive.layout.PaneAdaptedValue
import androidx.compose.material3.adaptive.layout.ThreePaneScaffoldValue
import androidx.compose.material3.adaptive.layout.calculatePaneScaffoldDirectiveWithTwoPanesOnMediumWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.kfpun.twaqi.ui.common.EmptyState

/** Both panes, always: a hideable list would open a tablet in portrait on an empty page (iOS `AdaptiveNavigation`). */
private val BOTH_PANES = ThreePaneScaffoldValue(
    primary = PaneAdaptedValue.Expanded,
    secondary = PaneAdaptedValue.Expanded,
    tertiary = PaneAdaptedValue.Hidden
)

/**
 * Search, Favourites and Help in a wide window (FOX-119, iOS `AdaptiveNavigation`): the list, and
 * beside it the chosen page, or the [placeholder] until something is chosen. Two panes from medium
 * width up, as iOS splits at the regular size class. The list ends on the fold of an unfolded
 * foldable, flat or half open, so neither pane is bent across it (iOS `FoldLine`).
 */
@Composable
fun ListDetailLayout(
    list: @Composable (Modifier) -> Unit,
    detail: (@Composable (Modifier) -> Unit)?,
    placeholder: @Composable () -> Unit,
    modifier: Modifier = Modifier
) {
    val directive = calculatePaneScaffoldDirectiveWithTwoPanesOnMediumWidth(
        currentWindowAdaptiveInfo(),
        HingePolicy.AlwaysAvoid
    ).copy(horizontalPartitionSpacerSize = 0.dp)
    ListDetailPaneScaffold(
        directive = directive,
        value = BOTH_PANES,
        listPane = {
            AnimatedPane {
                Row(Modifier.fillMaxSize()) {
                    list(Modifier.weight(1f))
                    VerticalDivider()
                }
            }
        },
        detailPane = {
            AnimatedPane {
                if (detail != null) detail(Modifier.fillMaxSize()) else placeholder()
            }
        },
        modifier = modifier
    )
}

/** The second pane before anything is chosen (iOS `EmptyStateView` in `AdaptiveNavigation`). */
@Composable
fun SelectionPlaceholder(@DrawableRes icon: Int, message: String) {
    Box(Modifier.fillMaxSize().statusBarsPadding(), contentAlignment = Alignment.Center) {
        EmptyState(icon, message, Modifier.align(Alignment.Center))
    }
}
