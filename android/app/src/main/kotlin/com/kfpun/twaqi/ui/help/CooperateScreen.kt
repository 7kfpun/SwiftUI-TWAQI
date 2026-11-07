package com.kfpun.twaqi.ui.help

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.kfpun.twaqi.R
import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.cooperate.CooperateForm
import com.kfpun.twaqi.cooperate.CooperateViewModel
import com.kfpun.twaqi.cooperate.CooperationType
import com.kfpun.twaqi.cooperate.OkHttpCooperateRepository
import com.kfpun.twaqi.forms.ClientInfo
import com.kfpun.twaqi.forms.FormError

/**
 * Business partner enquiry form (iOS `CooperateView`), sent to Directus `twaqi_cooperate`. App and
 * device details are added automatically and never shown.
 */
@Composable
fun CooperateScreen(onBack: () -> Unit) {
    val appContext = LocalContext.current.applicationContext
    val viewModel = viewModel {
        CooperateViewModel(
            repository = OkHttpCooperateRepository(),
            clientInfo = { ClientInfo.current(appContext) },
            logEvent = { name, parameters -> Analytics.logEvent(appContext, name, parameters) }
        )
    }
    LaunchedEffect(Unit) { Analytics.logEvent(appContext, Analytics.OPEN_COOPERATE_FORM) }

    HelpPage(title = stringResource(R.string.cooperate_title), onBack = onBack) { padding ->
        CooperateContent(
            form = viewModel.form,
            isSending = viewModel.isSending,
            canSend = viewModel.canSend,
            onChange = viewModel::update,
            onSend = viewModel::send,
            padding = padding
        )
    }

    if (viewModel.showingSuccess) {
        AlertDialog(
            onDismissRequest = {},
            title = { Text(stringResource(R.string.cooperate_sent_title)) },
            text = { Text(stringResource(R.string.cooperate_sent_message)) },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.acknowledgeSent()
                    onBack()
                }) { Text(stringResource(android.R.string.ok)) }
            }
        )
    }

    viewModel.failure?.let { failure ->
        AlertDialog(
            onDismissRequest = viewModel::dismissFailure,
            title = { Text(stringResource(R.string.cooperate_error_title)) },
            text = {
                Text(
                    stringResource(
                        if (failure ==
                            FormError.Offline
                        ) {
                            R.string.feedback_error_offline
                        } else {
                            R.string.feedback_error_generic
                        }
                    )
                )
            },
            confirmButton = {
                TextButton(onClick = viewModel::retry) { Text(stringResource(R.string.feedback_try_again)) }
            },
            dismissButton = {
                TextButton(onClick = viewModel::dismissFailure) { Text(stringResource(R.string.feedback_cancel)) }
            }
        )
    }
}

@Composable
internal fun CooperateContent(
    form: CooperateForm,
    isSending: Boolean,
    canSend: Boolean,
    onChange: ((CooperateForm) -> CooperateForm) -> Unit,
    onSend: () -> Unit,
    padding: androidx.compose.foundation.layout.PaddingValues
) {
    val enabled = !isSending
    HelpList(padding) {
        item(key = "type") {
            SectionHeader(stringResource(R.string.cooperate_intro_header))
            TypePicker(form.cooperationType, enabled) { type -> onChange { it.copy(cooperationType = type) } }
            SectionFooter(stringResource(R.string.cooperate_intro_footer))
        }
        item(key = "company") {
            SectionHeader(stringResource(R.string.cooperate_company_header), required = true)
            FormField(
                form.company,
                R.string.cooperate_company_placeholder,
                enabled,
                capitalization = KeyboardCapitalization.Words
            ) { value -> onChange { it.copy(company = value) } }
            FormField(
                form.website,
                R.string.cooperate_website_placeholder,
                enabled,
                keyboardType = KeyboardType.Uri
            ) { value ->
                onChange { it.copy(website = value) }
            }
        }
        item(key = "contact") {
            SectionHeader(stringResource(R.string.cooperate_contact_header), required = true)
            FormField(
                form.name,
                R.string.cooperate_name_placeholder,
                enabled,
                capitalization = KeyboardCapitalization.Words
            ) { value ->
                onChange { it.copy(name = value) }
            }
            FormField(
                form.jobTitle,
                R.string.cooperate_job_title_placeholder,
                enabled,
                capitalization = KeyboardCapitalization.Words
            ) { value -> onChange { it.copy(jobTitle = value) } }
            FormField(
                form.email,
                R.string.feedback_email_placeholder,
                enabled,
                keyboardType = KeyboardType.Email,
                isError = form.showsEmailError
            ) { value -> onChange { it.copy(email = value) } }
            FormField(
                form.phone,
                R.string.cooperate_phone_placeholder,
                enabled,
                keyboardType = KeyboardType.Phone
            ) { value ->
                onChange { it.copy(phone = value) }
            }
            if (form.showsEmailError) {
                SectionFooter(stringResource(R.string.feedback_email_invalid), color = MaterialTheme.colorScheme.error)
            } else {
                SectionFooter(stringResource(R.string.cooperate_contact_footer))
            }
        }
        item(key = "message") {
            SectionHeader(stringResource(R.string.cooperate_message_header), required = true)
            OutlinedTextField(
                value = form.message,
                onValueChange = { value -> onChange { it.copy(message = value) } },
                placeholder = { Text(stringResource(R.string.cooperate_message_placeholder)) },
                enabled = enabled,
                minLines = 6,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)
            )
        }
        item(key = "send") {
            Column(Modifier.padding(top = 24.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Button(
                    onClick = onSend,
                    enabled = canSend,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)
                ) {
                    if (isSending) {
                        CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    } else {
                        Text(stringResource(R.string.feedback_send))
                    }
                }
                SectionFooter(stringResource(R.string.cooperate_privacy_footer))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TypePicker(selected: CooperationType?, enabled: Boolean, onSelect: (CooperationType) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { if (enabled) expanded = it },
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
    ) {
        OutlinedTextField(
            value = selected?.let { stringResource(it.title) } ?: stringResource(R.string.cooperate_type_choose),
            onValueChange = {},
            readOnly = true,
            enabled = enabled,
            label = { Text(requiredText(stringResource(R.string.cooperate_type), required = true)) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier.fillMaxWidth().menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable, enabled)
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            CooperationType.entries.forEach { type ->
                DropdownMenuItem(
                    text = { Text(stringResource(type.title)) },
                    onClick = {
                        expanded = false
                        onSelect(type)
                    }
                )
            }
        }
    }
}

@Composable
private fun FormField(
    value: String,
    @StringRes placeholder: Int,
    enabled: Boolean,
    keyboardType: KeyboardType = KeyboardType.Text,
    capitalization: KeyboardCapitalization = KeyboardCapitalization.None,
    isError: Boolean = false,
    onValueChange: (String) -> Unit
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = { Text(stringResource(placeholder)) },
        enabled = enabled,
        singleLine = true,
        isError = isError,
        keyboardOptions = KeyboardOptions(
            capitalization = capitalization,
            autoCorrectEnabled = keyboardType == KeyboardType.Text,
            keyboardType = keyboardType,
            imeAction = ImeAction.Next
        ),
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)
    )
}

@get:StringRes
private val CooperationType.title: Int
    get() = when (this) {
        CooperationType.ADVERTISING -> R.string.cooperate_type_advertising
        CooperationType.DATA_API -> R.string.cooperate_type_data_api
        CooperationType.SPONSORSHIP -> R.string.cooperate_type_sponsorship
        CooperationType.MEDIA -> R.string.cooperate_type_media
        CooperationType.OTHER -> R.string.cooperate_type_other
    }
