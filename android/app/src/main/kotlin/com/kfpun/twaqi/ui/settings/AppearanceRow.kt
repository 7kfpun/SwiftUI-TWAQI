package com.kfpun.twaqi.ui.settings

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.kfpun.twaqi.R
import com.kfpun.twaqi.settings.AppAppearance
import com.kfpun.twaqi.settings.AppAppearanceStore
import com.kfpun.twaqi.ui.help.ChoiceRow

/** Help › Appearance (iOS `HelpView.appearanceSection`, FOX-43): System, Light or Dark for every screen. */
@Composable
fun AppearanceRow() {
    val context = LocalContext.current
    var selected by remember { mutableStateOf(AppAppearanceStore.current(context)) }
    ChoiceRow(
        label = stringResource(R.string.help_appearance),
        options = AppAppearance.entries,
        selected = selected,
        optionLabel = { appearanceName(it) },
        onSelect = { appearance ->
            selected = appearance
            AppAppearanceStore.set(context, appearance)
        }
    )
}

@Composable
private fun appearanceName(appearance: AppAppearance): String = stringResource(
    when (appearance) {
        AppAppearance.SYSTEM -> R.string.help_appearance_system
        AppAppearance.LIGHT -> R.string.help_appearance_light
        AppAppearance.DARK -> R.string.help_appearance_dark
    }
)
