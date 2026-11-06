package com.kfpun.twaqi.ui.help

import androidx.activity.compose.LocalActivity
import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import com.kfpun.twaqi.R
import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.feedback.FeedbackForm
import com.kfpun.twaqi.feedback.FeedbackSource
import com.kfpun.twaqi.feedback.FeedbackSubmission
import com.kfpun.twaqi.feedback.FeedbackViewModel
import com.kfpun.twaqi.feedback.OkHttpFeedbackRepository
import com.kfpun.twaqi.forms.ClientInfo
import com.kfpun.twaqi.forms.FormError
import com.kfpun.twaqi.review.ReviewPrompt
import com.kfpun.twaqi.settings.InstallPreferences

/**
 * The feedback form (iOS `FeedbackView`), sent to Directus `twaqi_feedback` with
 * `platform = android`. App and device details are added automatically and never shown.
 * [source] is where it was opened from, for `open_feedback_form`.
 */
@Composable
fun FeedbackScreen(source: FeedbackSource, onBack: () -> Unit) {
    val appContext = LocalContext.current.applicationContext
    val activity = LocalActivity.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val viewModel = viewModel {
        FeedbackViewModel(
            repository = OkHttpFeedbackRepository(),
            clientInfo = { ClientInfo.current(appContext) },
            anonymousId = { InstallPreferences.anonymousId(appContext) },
            logEvent = { name, parameters -> Analytics.logEvent(appContext, name, parameters) }
        )
    }
    // Once per visit, not again on rotation.
    var logged by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        if (!logged) {
            logged = true
            Analytics.logEvent(appContext, Analytics.OPEN_FEEDBACK_FORM, source.openFormEventParameters)
        }
    }

    // A 4- or 5-star feedback: Play's review prompt over the thank-you, unless the app has left
    // the foreground meanwhile.
    LaunchedEffect(viewModel.reviewPromptDue) {
        if (!viewModel.reviewPromptDue) return@LaunchedEffect
        val launch = activity != null && lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
        if (launch && activity != null) ReviewPrompt.request(activity)
        viewModel.onReviewPromptHandled(launched = launch)
    }

    val finish = {
        viewModel.acknowledgeSent()
        onBack()
    }

    HelpPage(title = stringResource(R.string.feedback_title), onBack = onBack) { padding ->
        FeedbackContent(
            form = viewModel.form,
            isSending = viewModel.isSending,
            canSend = viewModel.canSend,
            onChange = viewModel::update,
            onSend = viewModel::send,
            padding = padding
        )
    }

    viewModel.sent?.let { sent ->
        val offersStoreReview = viewModel.offersStoreReview
        AlertDialog(
            onDismissRequest = {},
            title = { Text(stringResource(R.string.feedback_sent_title)) },
            text = { Text(stringResource(FeedbackSubmission.thankYouMessage(offersStoreReview, sent.email))) },
            confirmButton = {
                TextButton(onClick = finish) { Text(stringResource(android.R.string.ok)) }
            },
            dismissButton = if (offersStoreReview) {
                {
                    // User-initiated only, as on iOS.
                    TextButton(onClick = {
                        viewModel.onWriteReviewTapped()
                        ReviewPrompt.openStoreListing(activity ?: appContext)
                        finish()
                    }) { Text(stringResource(R.string.feedback_rate_on_app_store)) }
                }
            } else {
                null
            }
        )
    }

    viewModel.failure?.let { failure ->
        AlertDialog(
            onDismissRequest = viewModel::dismissFailure,
            title = { Text(stringResource(R.string.feedback_error_title)) },
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
internal fun FeedbackContent(
    form: FeedbackForm,
    isSending: Boolean,
    canSend: Boolean,
    onChange: ((FeedbackForm) -> FeedbackForm) -> Unit,
    onSend: () -> Unit,
    padding: PaddingValues
) {
    val enabled = !isSending
    HelpList(padding) {
        item(key = "rating") {
            SectionHeader(stringResource(R.string.feedback_rating_header), required = true)
            StarRating(form.rating, enabled) { stars -> onChange { it.copy(rating = stars) } }
        }
        item(key = "message") {
            SectionHeader(stringResource(R.string.feedback_message_header), required = true)
            MultilineField(form.message, R.string.feedback_message_placeholder, enabled, minLines = 5) { value ->
                onChange { it.copy(message = value) }
            }
        }
        item(key = "other") {
            SectionHeader(stringResource(R.string.feedback_other_header))
            MultilineField(form.otherFeedback, R.string.feedback_optional, enabled, minLines = 3) { value ->
                onChange { it.copy(otherFeedback = value) }
            }
        }
        item(key = "interview") {
            ListItem(
                headlineContent = { Text(stringResource(R.string.feedback_interview)) },
                trailingContent = {
                    Switch(checked = form.interviewInterest, onCheckedChange = null, enabled = enabled)
                },
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                modifier = Modifier.padding(top = 16.dp).toggleable(
                    value = form.interviewInterest,
                    enabled = enabled,
                    role = Role.Switch
                ) { on -> onChange { it.copy(interviewInterest = on) } }
            )
            SectionFooter(stringResource(R.string.feedback_interview_footer))
        }
        item(key = "contact") {
            Column(Modifier.padding(top = 16.dp)) {
                OutlinedTextField(
                    value = form.name,
                    onValueChange = { value -> onChange { it.copy(name = value) } },
                    placeholder = { Text(stringResource(R.string.feedback_name_placeholder)) },
                    enabled = enabled,
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Words,
                        imeAction = ImeAction.Next
                    ),
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)
                )
                OutlinedTextField(
                    value = form.email,
                    onValueChange = { value -> onChange { it.copy(email = value) } },
                    placeholder = { Text(stringResource(R.string.feedback_email_placeholder)) },
                    enabled = enabled,
                    singleLine = true,
                    isError = form.showsEmailError,
                    keyboardOptions = KeyboardOptions(
                        autoCorrectEnabled = false,
                        keyboardType = KeyboardType.Email,
                        imeAction = ImeAction.Done
                    ),
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)
                )
                if (form.showsEmailError) {
                    SectionFooter(
                        stringResource(R.string.feedback_email_invalid),
                        color = MaterialTheme.colorScheme.error
                    )
                } else {
                    SectionFooter(stringResource(R.string.feedback_email_footer))
                }
            }
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
                SectionFooter(stringResource(R.string.feedback_privacy_footer))
            }
        }
    }
}

/** Five stars; the [rating]th and those before it are filled (iOS: yellow). */
@Composable
private fun StarRating(rating: Int?, enabled: Boolean, onSelect: (Int) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally)
    ) {
        (1..5).forEach { star ->
            val filled = star <= (rating ?: 0)
            IconButton(
                onClick = { onSelect(star) },
                enabled = enabled,
                modifier = Modifier.semantics { selected = star == rating }
            ) {
                Icon(
                    painterResource(if (filled) R.drawable.ic_feedback_star else R.drawable.ic_feedback_star_outline),
                    contentDescription = stringResource(R.string.feedback_rating_stars, star),
                    tint = if (filled) STAR_YELLOW else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(32.dp)
                )
            }
        }
    }
}

@Composable
private fun MultilineField(
    value: String,
    @StringRes placeholder: Int,
    enabled: Boolean,
    minLines: Int,
    onValueChange: (String) -> Unit
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = { Text(stringResource(placeholder)) },
        enabled = enabled,
        minLines = minLines,
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)
    )
}

/** iOS `Color.yellow`. */
private val STAR_YELLOW = Color(0xFFFFCC00)
