package com.kfpun.twaqi.feedback

import com.kfpun.twaqi.cooperate.testClient
import com.kfpun.twaqi.forms.FormError
import com.kfpun.twaqi.forms.SubmitResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class FeedbackViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    private val sent = mutableListOf<FeedbackSubmission>()
    private val events = mutableListOf<Pair<String, Map<String, Any>>>()
    private var result: SubmitResult = SubmitResult.Sent

    private val completeForm = FeedbackForm(rating = 5, message = "More stations", email = "me@example.com")

    private fun viewModel(form: FeedbackForm = completeForm) = FeedbackViewModel(
        repository = { submission ->
            sent += submission
            result
        },
        clientInfo = { testClient },
        anonymousId = { "install-1" },
        logEvent = { name, parameters -> events += name to parameters }
    ).apply { update { form } }

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun test(body: suspend TestScope.() -> Unit) = runTest(dispatcher) { body() }

    @Test
    fun incompleteFormIsNotSent() = test {
        val model = viewModel(completeForm.copy(rating = null))

        assertFalse(model.canSend)
        model.send()
        runCurrent()

        assertTrue(sent.isEmpty())
    }

    @Test
    fun sentFeedbackLogsAndShowsTheThankYou() = test {
        val model = viewModel(completeForm.copy(rating = 3, interviewInterest = true))

        model.send()
        runCurrent()

        assertEquals("android", sent.single().platform)
        assertEquals("install-1", sent.single().metaJson?.get("anonymous_id"))
        assertEquals(
            listOf("submit_feedback" to mapOf("platform" to "android", "rating" to 3, "interview_interest" to true)),
            events
        )
        assertEquals(sent.single(), model.sent)
        assertFalse(model.offersStoreReview)
        assertFalse(model.isSending)
    }

    @Test
    fun failureLogsTheReasonAndKeepsTheForm() = test {
        result = SubmitResult.Failed(FormError.Offline)
        val model = viewModel()

        model.send()
        runCurrent()

        assertEquals(FormError.Offline, model.failure)
        assertEquals(listOf("submit_feedback_failed" to mapOf("reason" to "offline")), events)
        assertEquals(completeForm, model.form)
        assertNull(model.sent)

        result = SubmitResult.Sent
        model.retry()
        runCurrent()
        assertNull(model.failure)
        assertEquals(2, sent.size)
    }

    @Test
    fun highRatingAsksForTheReviewAfterTheThankYouShows() = test {
        val model = viewModel()

        model.send()
        runCurrent()
        assertTrue(model.offersStoreReview)
        assertFalse(model.reviewPromptDue)

        advanceTimeBy(FeedbackViewModel.REVIEW_PROMPT_DELAY_MS + 1)
        assertTrue(model.reviewPromptDue)

        model.onReviewPromptHandled(launched = true)
        assertFalse(model.reviewPromptDue)
        assertEquals("review_requested" to mapOf("source" to "feedback", "rating" to 5), events.last())
    }

    @Test
    fun reviewIsNotLoggedWhenTheAppLeftTheForeground() = test {
        val model = viewModel()
        model.send()
        advanceTimeBy(FeedbackViewModel.REVIEW_PROMPT_DELAY_MS + 1)

        model.onReviewPromptHandled(launched = false)

        assertFalse(events.any { it.first == "review_requested" })
    }

    @Test
    fun closingTheThankYouWithinTheDelaySkipsTheReview() = test {
        val model = viewModel()
        model.send()
        runCurrent()

        model.acknowledgeSent()
        advanceTimeBy(FeedbackViewModel.REVIEW_PROMPT_DELAY_MS * 2)

        assertFalse(model.reviewPromptDue)
        assertEquals(FeedbackForm(), model.form)
        assertNull(model.sent)
    }

    @Test
    fun lowRatingNeverAsksForAReview() = test {
        val model = viewModel(completeForm.copy(rating = 3))
        model.send()
        advanceTimeBy(FeedbackViewModel.REVIEW_PROMPT_DELAY_MS * 2)

        assertFalse(model.reviewPromptDue)
    }

    @Test
    fun rateOnGooglePlayIsLogged() = test {
        val model = viewModel()
        model.send()
        runCurrent()

        model.onWriteReviewTapped()

        assertEquals("write_review_tapped" to mapOf("source" to "feedback"), events.last())
    }
}
