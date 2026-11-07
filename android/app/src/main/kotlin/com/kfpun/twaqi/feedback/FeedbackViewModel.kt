package com.kfpun.twaqi.feedback

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.forms.ClientInfo
import com.kfpun.twaqi.forms.FormError
import com.kfpun.twaqi.forms.SubmitResult
import com.kfpun.twaqi.review.ReviewPolicy
import com.kfpun.twaqi.review.ReviewRequestSource
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * State and sending of the feedback form (iOS `FeedbackView`). [logEvent] is `Analytics.logEvent`
 * bound to a context; [anonymousId] is this install's id.
 */
class FeedbackViewModel(
    private val repository: FeedbackRepository,
    private val clientInfo: () -> ClientInfo,
    private val anonymousId: () -> String?,
    private val logEvent: (String, Map<String, Any>) -> Unit
) : ViewModel() {
    var form by mutableStateOf(FeedbackForm())
        private set

    var isSending by mutableStateOf(false)
        private set

    /** What was sent, while the thank-you shows; null otherwise. */
    var sent by mutableStateOf<FeedbackSubmission?>(null)
        private set

    /** Why the last send failed; the screen shows the error dialog with Try again. */
    var failure by mutableStateOf<FormError?>(null)
        private set

    /**
     * The thank-you has shown for [REVIEW_PROMPT_DELAY_MS] after a 4- or 5-star feedback: the
     * screen asks Play for the review prompt, then calls [onReviewPromptHandled].
     */
    var reviewPromptDue by mutableStateOf(false)
        private set

    private var reviewPromptJob: Job? = null

    val canSend: Boolean get() = !isSending && form.isComplete

    /** The thank-you offers "Rate on Google Play" (4 or 5 stars). */
    val offersStoreReview: Boolean
        get() = sent?.let { ReviewPolicy.shouldRequestReviewAfterFeedback(it.rating) } ?: false

    fun update(transform: (FeedbackForm) -> FeedbackForm) {
        if (!isSending) form = transform(form)
    }

    fun send() {
        if (!canSend) return
        val submission = form.submission(clientInfo(), anonymousId()) ?: return
        isSending = true
        viewModelScope.launch {
            when (val result = repository.submit(submission)) {
                SubmitResult.Sent -> {
                    logEvent(Analytics.SUBMIT_FEEDBACK, submission.submitEventParameters)
                    isSending = false
                    sent = submission
                    // After the thank-you appears, not over the form; 4–5 stars only.
                    if (ReviewPolicy.shouldRequestReviewAfterFeedback(submission.rating)) {
                        reviewPromptJob = launch {
                            delay(REVIEW_PROMPT_DELAY_MS)
                            // Closed within the delay: not over the screen behind.
                            if (sent != null) reviewPromptDue = true
                        }
                    }
                }

                is SubmitResult.Failed -> {
                    logEvent(Analytics.SUBMIT_FEEDBACK_FAILED, mapOf("reason" to result.error.reason))
                    isSending = false
                    failure = result.error
                }
            }
        }
    }

    /**
     * The screen asked Play for the prompt ([launched]), or dropped it because the app had left
     * the foreground (e.g. "Rate on Google Play" was tapped first).
     */
    fun onReviewPromptHandled(launched: Boolean) {
        if (!reviewPromptDue) return
        reviewPromptDue = false
        val rating = sent?.rating ?: return
        if (launched) {
            logEvent(
                Analytics.REVIEW_REQUESTED,
                mapOf("source" to ReviewRequestSource.FEEDBACK.analyticsName, "rating" to rating)
            )
        }
    }

    /** "Rate on Google Play" in the thank-you; the screen opens the listing and closes the form. */
    fun onWriteReviewTapped() {
        logEvent(Analytics.WRITE_REVIEW_TAPPED, mapOf("source" to ReviewRequestSource.FEEDBACK.analyticsName))
    }

    /** Closes the thank-you: the form is emptied so it can't be sent twice. */
    fun acknowledgeSent() {
        reviewPromptJob?.cancel()
        reviewPromptDue = false
        sent = null
        form = FeedbackForm()
    }

    fun dismissFailure() {
        failure = null
    }

    fun retry() {
        failure = null
        send()
    }

    companion object {
        /** How long the thank-you shows before the review prompt (iOS: 1 s). */
        const val REVIEW_PROMPT_DELAY_MS = 1_000L
    }
}
