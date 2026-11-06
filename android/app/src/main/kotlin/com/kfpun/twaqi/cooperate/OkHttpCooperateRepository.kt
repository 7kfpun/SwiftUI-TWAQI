package com.kfpun.twaqi.cooperate

import com.kfpun.twaqi.BuildConfig
import com.kfpun.twaqi.data.remote.ApiClient
import com.kfpun.twaqi.forms.DirectusForms
import com.kfpun.twaqi.forms.SubmitResult
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * Posts enquiries to Directus `items/twaqi_cooperate`, create-only, with the data layer's OkHttp
 * client settings (FOX-53, `ApiClient.defaultHttpClient`).
 */
class OkHttpCooperateRepository(
    private val baseUrl: String = BuildConfig.DIRECTUS_URL,
    private val cooperateToken: String = BuildConfig.DIRECTUS_COOPERATE_TOKEN,
    private val feedbackToken: String = BuildConfig.DIRECTUS_FEEDBACK_TOKEN,
    private val http: OkHttpClient = ApiClient.defaultHttpClient()
) : CooperateRepository {

    override suspend fun submit(submission: CooperateSubmission): SubmitResult =
        DirectusForms.send(makeRequest(baseUrl, cooperateToken, feedbackToken, submission), http)

    companion object {
        const val COLLECTION_PATH = "items/twaqi_cooperate"

        /**
         * Uses the cooperate token when the build sets one, else the feedback token, whose role is
         * expected to have create on `twaqi_cooperate` too (as on iOS). Null without a URL or token.
         */
        fun makeRequest(
            baseUrl: String?,
            cooperateToken: String?,
            feedbackToken: String?,
            submission: CooperateSubmission
        ): Request? {
            val token = listOf(cooperateToken, feedbackToken).firstNotNullOfOrNull {
                it?.trim()?.takeIf(String::isNotEmpty)
            }
            return DirectusForms.createRequest(baseUrl, token, COLLECTION_PATH, submission.toJson())
        }
    }
}
