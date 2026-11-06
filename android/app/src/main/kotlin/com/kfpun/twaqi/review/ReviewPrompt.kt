package com.kfpun.twaqi.review

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.util.Log
import androidx.core.content.edit
import com.google.android.play.core.review.ReviewManagerFactory
import com.kfpun.twaqi.BuildConfig
import com.kfpun.twaqi.analytics.Analytics

/** What asked for the review prompt, the `source` of `review_requested` (iOS `ReviewRequestSource`). */
enum class ReviewRequestSource(val analyticsName: String) {
    /** Every [ReviewPolicy.REVIEW_REQUEST_INTERVAL] app opens. */
    APP_OPENS("app_opens"),

    /** Right after a 4- or 5-star feedback was sent. */
    FEEDBACK("feedback")
}

/** When to ask Play for the review prompt (iOS `StoreReviewHelper`, FOX-45 and FOX-80). */
object ReviewPolicy {
    /** Ask every this many app opens, as iOS does since FOX-45. */
    const val REVIEW_REQUEST_INTERVAL = 20

    /** Lowest feedback rating (of 1–5 stars) that asks for a review. */
    const val FEEDBACK_REVIEW_MINIMUM_RATING = 4

    /** Opens 20, 40, 60 and so on. Play decides whether the prompt shows, so asking often is fine. */
    fun shouldRequestReview(appOpenCount: Int): Boolean =
        appOpenCount > 0 && appOpenCount % REVIEW_REQUEST_INTERVAL == 0

    /** 4 or 5 stars only; call it once the feedback was sent. */
    fun shouldRequestReviewAfterFeedback(rating: Int): Boolean = rating in FEEDBACK_REVIEW_MINIMUM_RATING..5
}

/** Where the open count is kept. */
interface AppOpenStore {
    var appOpenedCount: Int
}

/** Counts app opens (iOS `StoreReviewHelper.incrementAppOpenedCount`). */
class AppOpenCounter(private val store: AppOpenStore) {
    /** Counts this open and returns the new total. */
    fun recordAppOpen(): Int = (store.appOpenedCount.coerceAtLeast(0) + 1).also { store.appOpenedCount = it }
}

/**
 * The Play In-App Review prompt. Play decides whether it shows and limits how often, so a
 * request may show nothing; `review_requested` counts requests, not prompts.
 */
object ReviewPrompt {
    private const val FILE = "review_prompt"

    /**
     * Counts this app open and, on every 20th, asks Play for the prompt. Call once per process
     * start, from the first activity.
     */
    fun onAppOpen(activity: Activity, logEvent: (String, Map<String, Any>) -> Unit) {
        val count = AppOpenCounter(SharedAppOpenStore(activity.getSharedPreferences(FILE, Context.MODE_PRIVATE)))
            .recordAppOpen()
        if (!ReviewPolicy.shouldRequestReview(count)) return
        logEvent(
            Analytics.REVIEW_REQUESTED,
            mapOf("source" to ReviewRequestSource.APP_OPENS.analyticsName, "app_open_count" to count)
        )
        request(activity)
    }

    /** Asks Play for the prompt over [activity]. Fails quietly where Play isn't there (an emulator). */
    fun request(activity: Activity) {
        val manager = ReviewManagerFactory.create(activity)
        manager.requestReviewFlow().addOnCompleteListener { task ->
            if (!task.isSuccessful) {
                if (BuildConfig.DEBUG) Log.d("ReviewPrompt", "no review flow", task.exception)
                return@addOnCompleteListener
            }
            if (activity.isFinishing || activity.isDestroyed) return@addOnCompleteListener
            manager.launchReviewFlow(activity, task.result)
        }
    }

    /** This app's Play listing, for the user-initiated "Rate on Google Play" (iOS `writeReviewURL`). */
    val storeListingUrl: String get() = "https://play.google.com/store/apps/details?id=${BuildConfig.APPLICATION_ID}"

    /** Opens the listing in the Play Store app, or in the browser without it. */
    fun openStoreListing(context: Context) {
        val market = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=${BuildConfig.APPLICATION_ID}"))
        val web = Intent(Intent.ACTION_VIEW, Uri.parse(storeListingUrl))
        listOf(market, web).forEach { intent ->
            if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
                return
            } catch (_: ActivityNotFoundException) {
            }
        }
    }
}

private class SharedAppOpenStore(private val preferences: SharedPreferences) : AppOpenStore {
    override var appOpenedCount: Int
        get() = preferences.getInt(KEY, 0)
        set(value) = preferences.edit { putInt(KEY, value) }

    private companion object {
        /** The iOS UserDefaults key. */
        const val KEY = "appOpenedCount"
    }
}
