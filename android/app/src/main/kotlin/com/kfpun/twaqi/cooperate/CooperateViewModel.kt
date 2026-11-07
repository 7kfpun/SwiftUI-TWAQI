package com.kfpun.twaqi.cooperate

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.forms.ClientInfo
import com.kfpun.twaqi.forms.FormError
import com.kfpun.twaqi.forms.SubmitResult
import kotlinx.coroutines.launch

/**
 * State and sending of the business partner form (iOS `CooperateView`). [logEvent] is
 * `Analytics.logEvent` bound to a context.
 */
class CooperateViewModel(
    private val repository: CooperateRepository,
    private val clientInfo: () -> ClientInfo,
    private val logEvent: (String, Map<String, String>) -> Unit
) : ViewModel() {
    var form by mutableStateOf(CooperateForm())
        private set

    var isSending by mutableStateOf(false)
        private set

    /** The enquiry went through; the screen shows the "sent" dialog. */
    var showingSuccess by mutableStateOf(false)
        private set

    /** Why the last send failed; the screen shows the error dialog with Try again. */
    var failure by mutableStateOf<FormError?>(null)
        private set

    val canSend: Boolean get() = !isSending && form.isComplete

    fun update(transform: (CooperateForm) -> CooperateForm) {
        if (!isSending) form = transform(form)
    }

    fun send() {
        if (!canSend) return
        val submission = form.submission(clientInfo()) ?: return
        isSending = true
        viewModelScope.launch {
            when (val result = repository.submit(submission)) {
                SubmitResult.Sent -> {
                    logEvent(Analytics.SUBMIT_COOPERATE, mapOf("cooperation_type" to submission.cooperationType))
                    showingSuccess = true
                }

                is SubmitResult.Failed -> {
                    logEvent(Analytics.SUBMIT_COOPERATE_FAILED, mapOf("reason" to result.error.reason))
                    failure = result.error
                }
            }
            isSending = false
        }
    }

    /** OK on the "sent" dialog: the form is emptied so it can't be sent twice. */
    fun acknowledgeSent() {
        showingSuccess = false
        form = CooperateForm()
    }

    fun dismissFailure() {
        failure = null
    }

    fun retry() {
        failure = null
        send()
    }
}
