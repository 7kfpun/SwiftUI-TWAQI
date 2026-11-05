package com.kfpun.twaqi.feedback

import com.kfpun.twaqi.BuildConfig
import com.kfpun.twaqi.data.remote.ApiClient
import com.kfpun.twaqi.forms.DirectusForms
import com.kfpun.twaqi.forms.SubmitResult
import okhttp3.OkHttpClient
import okhttp3.Request

/** Sends feedback (iOS `FeedbackService`). */
fun interface FeedbackRepository {
    suspend fun submit(submission: FeedbackSubmission): SubmitResult
}

/**
 * Posts feedback to Directus `items/twaqi_feedback`, create-only, with `DIRECTUS_URL` and
 * `DIRECTUS_FEEDBACK_TOKEN` from `secrets.properties`.
 */
class OkHttpFeedbackRepository(
    private val baseUrl: String = BuildConfig.DIRECTUS_URL,
    private val token: String = BuildConfig.DIRECTUS_FEEDBACK_TOKEN,
    private val http: OkHttpClient = ApiClient.defaultHttpClient()
) : FeedbackRepository {

    override suspend fun submit(submission: FeedbackSubmission): SubmitResult =
        DirectusForms.send(makeRequest(baseUrl, token, submission), http)

    companion object {
        const val COLLECTION_PATH = "items/twaqi_feedback"

        /** Null without a Directus URL or token. */
        fun makeRequest(baseUrl: String?, token: String?, submission: FeedbackSubmission): Request? =
            DirectusForms.createRequest(baseUrl, token, COLLECTION_PATH, submission.toJson())
    }
}
