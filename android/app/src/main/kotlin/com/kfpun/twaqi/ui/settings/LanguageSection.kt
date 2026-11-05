package com.kfpun.twaqi.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.kfpun.twaqi.R
import com.kfpun.twaqi.locale.AppLanguage
import com.kfpun.twaqi.locale.AppLocale

/** Help › Language (iOS `HelpView.languageSection`); the Help screen will host it. */
@Composable
fun LanguageSection(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    var selected by remember { mutableStateOf(AppLocale.current(context)) }
    Column(modifier.selectableGroup()) {
        Text(
            text = stringResource(R.string.help_language),
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
        )
        AppLanguage.entries.forEach { language ->
            LanguageRow(
                label = languageName(language),
                selected = language == selected,
                onClick = {
                    if (language != selected) {
                        selected = language
                        AppLocale.set(context, language)
                    }
                }
            )
        }
    }
}

/** Each language in its own name, whatever the UI language, as on iOS. */
@Composable
private fun languageName(language: AppLanguage): String = when (language) {
    AppLanguage.SYSTEM -> stringResource(R.string.help_language_system)
    AppLanguage.TRADITIONAL_CHINESE -> "繁體中文"
    AppLanguage.ENGLISH -> "English"
}

@Composable
private fun LanguageRow(label: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .selectable(selected = selected, onClick = onClick, role = Role.RadioButton)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        RadioButton(selected = selected, onClick = null)
        Text(text = label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(start = 16.dp))
    }
}
