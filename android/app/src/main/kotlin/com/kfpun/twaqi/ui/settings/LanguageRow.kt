package com.kfpun.twaqi.ui.settings

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.kfpun.twaqi.R
import com.kfpun.twaqi.locale.AppLanguage
import com.kfpun.twaqi.locale.AppLocale
import com.kfpun.twaqi.ui.help.ChoiceRow

/** Help › Language (iOS `HelpView.languageSection`): the picker row; open activities restart in the choice. */
@Composable
fun LanguageRow() {
    val context = LocalContext.current
    var selected by remember { mutableStateOf(AppLocale.current(context)) }
    ChoiceRow(
        label = stringResource(R.string.help_language),
        options = AppLanguage.entries,
        selected = selected,
        optionLabel = { languageName(it) },
        onSelect = { language ->
            selected = language
            AppLocale.set(context, language)
        }
    )
}

/** Each language in its own name, whatever the UI language, as on iOS. */
@Composable
private fun languageName(language: AppLanguage): String = when (language) {
    AppLanguage.SYSTEM -> stringResource(R.string.help_language_system)
    AppLanguage.TRADITIONAL_CHINESE -> "繁體中文"
    AppLanguage.ENGLISH -> "English"
}
