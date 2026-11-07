package com.kfpun.twaqi.review

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `StoreReviewTests`. */
class ReviewPolicyTest {
    @Test
    fun requestsReviewEveryTwentyOpens() {
        listOf(20, 40, 60, 80, 100, 120, 1_000).forEach {
            assertTrue("open $it", ReviewPolicy.shouldRequestReview(appOpenCount = it))
        }
    }

    @Test
    fun doesNotRequestReviewBetweenMultiplesOfTwenty() {
        listOf(1, 9, 10, 11, 19, 21, 30, 50, 99, 101, 110, 1_010).forEach {
            assertFalse("open $it", ReviewPolicy.shouldRequestReview(appOpenCount = it))
        }
    }

    @Test
    fun doesNotRequestReviewForZeroOrNegativeCount() {
        assertFalse(ReviewPolicy.shouldRequestReview(appOpenCount = 0))
        assertFalse(ReviewPolicy.shouldRequestReview(appOpenCount = -20))
    }

    @Test
    fun requestsReviewAfterFourOrFiveStarFeedbackOnly() {
        assertTrue(ReviewPolicy.shouldRequestReviewAfterFeedback(4))
        assertTrue(ReviewPolicy.shouldRequestReviewAfterFeedback(5))
        listOf(-1, 0, 1, 2, 3, 6, 10).forEach {
            assertFalse("$it stars", ReviewPolicy.shouldRequestReviewAfterFeedback(it))
        }
    }

    @Test
    fun counterAddsOneEachOpenFromWhereItWas() {
        val store = object : AppOpenStore {
            override var appOpenedCount = 0
        }
        val counter = AppOpenCounter(store)

        assertEquals(1, counter.recordAppOpen())
        assertEquals(2, counter.recordAppOpen())
        assertEquals(2, store.appOpenedCount)

        // Twenty opens in: the review is due on the 20th.
        val due = (3..20).map { counter.recordAppOpen() }.filter(ReviewPolicy::shouldRequestReview)
        assertEquals(listOf(20), due)
    }

    @Test
    fun counterRecoversFromABadStoredValue() {
        val store = object : AppOpenStore {
            override var appOpenedCount = -5
        }

        assertEquals(1, AppOpenCounter(store).recordAppOpen())
    }

    @Test
    fun sourceNamesMatchIos() {
        assertEquals("app_opens", ReviewRequestSource.APP_OPENS.analyticsName)
        assertEquals("feedback", ReviewRequestSource.FEEDBACK.analyticsName)
    }
}
