package com.kfpun.twaqi.cooperate

import com.kfpun.twaqi.forms.FormError
import com.kfpun.twaqi.forms.SubmitResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class CooperateViewModelTest {
    private val sent = mutableListOf<CooperateSubmission>()
    private val events = mutableListOf<Pair<String, Map<String, String>>>()
    private var result: SubmitResult = SubmitResult.Sent

    private fun viewModel() = CooperateViewModel(
        repository = { submission ->
            sent += submission
            result
        },
        clientInfo = { testClient },
        logEvent = { name, parameters -> events += name to parameters }
    )

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun incompleteFormIsNotSent() {
        val model = viewModel()
        model.update { completeForm.copy(email = "ann@") }

        assertFalse(model.canSend)
        model.send()

        assertTrue(sent.isEmpty())
    }

    @Test
    fun sentEnquiryLogsItsTypeAndShowsSuccess() {
        val model = viewModel()
        model.update { completeForm }

        model.send()

        assertEquals("android", sent.single().platform)
        assertEquals(listOf("submit_cooperate" to mapOf("cooperation_type" to "advertising")), events)
        assertTrue(model.showingSuccess)
        assertFalse(model.isSending)

        // OK empties the form so it can't be sent twice.
        model.acknowledgeSent()
        assertFalse(model.showingSuccess)
        assertEquals(CooperateForm(), model.form)
    }

    @Test
    fun failureKeepsTheFormAndCanBeRetried() {
        result = SubmitResult.Failed(FormError.Offline)
        val model = viewModel()
        model.update { completeForm }

        model.send()

        assertEquals(FormError.Offline, model.failure)
        assertEquals(listOf("submit_cooperate_failed" to mapOf("reason" to "offline")), events)
        assertEquals(completeForm, model.form)

        result = SubmitResult.Sent
        model.retry()

        assertNull(model.failure)
        assertTrue(model.showingSuccess)
        assertEquals(2, sent.size)
    }
}
