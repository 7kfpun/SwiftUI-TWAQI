package com.kfpun.twaqi.ui.help

import android.content.ActivityNotFoundException
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.UriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.kfpun.twaqi.R

/** A Help sub-page: a top bar with a back arrow and [title] over [content]. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun HelpPage(title: String, onBack: () -> Unit, content: @Composable (PaddingValues) -> Unit) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            painterResource(R.drawable.ic_arrow_back),
                            contentDescription = stringResource(R.string.help_back)
                        )
                    }
                }
            )
        }
    ) { padding -> Box(Modifier.fillMaxSize()) { content(padding) } }
}

/** A list page made of sections, like an iOS grouped list. */
@Composable
internal fun HelpList(
    padding: PaddingValues,
    listState: LazyListState = rememberLazyListState(),
    content: LazyListScope.() -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        state = listState,
        contentPadding = PaddingValues(
            top = padding.calculateTopPadding(),
            bottom =
                padding.calculateBottomPadding() + 24.dp
        ),
        content = content
    )
}

/** A section header; [required] adds a red asterisk, as on the iOS forms. */
@Composable
internal fun SectionHeader(text: String, modifier: Modifier = Modifier, required: Boolean = false) {
    Text(
        text = requiredText(text, required),
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 24.dp, bottom = 4.dp)
    )
}

@Composable
internal fun requiredText(text: String, required: Boolean) = buildAnnotatedString {
    append(text)
    if (required) withStyle(SpanStyle(color = MaterialTheme.colorScheme.error)) { append(" *") }
}

/** The light text under a section. */
@Composable
internal fun SectionFooter(text: String, color: Color = MaterialTheme.colorScheme.onSurfaceVariant) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodySmall,
        color = color,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)
    )
}

/** Paragraph text of a guide. */
@Composable
internal fun GuideText(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodyMedium,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)
    )
}

/** A tappable row that opens a page or an action. */
@Composable
internal fun LinkRow(text: String, onClick: () -> Unit, emphasized: Boolean = false, external: Boolean = false) {
    ListItem(
        headlineContent = {
            Text(
                text,
                color = if (emphasized) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                fontWeight = if (emphasized) FontWeight.Medium else null
            )
        },
        trailingContent = {
            Icon(
                painterResource(if (external) R.drawable.ic_open_in_new else R.drawable.ic_chevron_right),
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(20.dp)
            )
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.clickable(role = Role.Button, onClick = onClick)
    )
}

/** A label with a value on the right. */
@Composable
internal fun ValueRow(label: String, value: String, modifier: Modifier = Modifier) {
    ListItem(
        headlineContent = { Text(label) },
        trailingContent = { Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant) },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = modifier
    )
}

/** A picker row (iOS `Picker` in a `Form`): the choice on the right, a menu of options on tap. */
@Composable
internal fun <T> ChoiceRow(
    label: String,
    options: List<T>,
    selected: T,
    optionLabel: @Composable (T) -> String,
    onSelect: (T) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        ListItem(
            headlineContent = { Text(label) },
            trailingContent = { Text(optionLabel(selected), color = MaterialTheme.colorScheme.primary) },
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            modifier = Modifier.clickable(role = Role.DropdownList) { expanded = true }
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(optionLabel(option)) },
                    leadingIcon = { RadioButton(selected = option == selected, onClick = null) },
                    onClick = {
                        expanded = false
                        if (option != selected) onSelect(option)
                    }
                )
            }
        }
    }
}

/** Opens [url] in the browser; does nothing on a device without one. */
internal fun UriHandler.openSafely(url: String) {
    try {
        openUri(url)
    } catch (_: ActivityNotFoundException) {
    } catch (_: IllegalArgumentException) {
    }
}
