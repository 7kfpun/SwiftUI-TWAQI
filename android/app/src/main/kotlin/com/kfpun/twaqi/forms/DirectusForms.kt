package com.kfpun.twaqi.forms

import java.io.IOException
import java.net.NoRouteToHostException
import java.net.UnknownHostException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * Helpers for the create-only forms the app posts to Directus (iOS `FeedbackSubmission` and
 * `FeedbackService`): the business partner form here, the feedback form with FOX-60.
 */
object FormText {
    /** Trimmed text, or null when blank, so optional fields are left out of the JSON rather than sent as "". */
    fun trimmed(text: String?): String? = text?.trim()?.takeIf { it.isNotEmpty() }

    /**
     * Loose on purpose, as on iOS: catches typos like a missing "@" or domain, and leaves the
     * rest to the server.
     */
    fun isValidEmail(text: String): Boolean {
        val value = text.trim()
        val parts = value.split("@")
        return parts.size == 2 &&
            parts[0].isNotEmpty() &&
            parts[1].contains('.') &&
            !parts[1].startsWith('.') &&
            !parts[1].endsWith('.') &&
            value.none { it.isWhitespace() }
    }
}

/** Why a create-only Directus form wasn't sent (iOS `FeedbackError`). */
sealed interface FormError {
    /** The Directus URL or token is missing from `secrets.properties`. */
    data object NotConfigured : FormError

    data object Offline : FormError

    data class Server(val statusCode: Int) : FormError

    data object Network : FormError

    /** The `reason` parameter of the `…_failed` analytics events, worded as iOS sends it. */
    val reason: String
        get() = when (this) {
            NotConfigured -> "notConfigured"
            Offline -> "offline"
            is Server -> "server(statusCode: $statusCode)"
            Network -> "network"
        }
}

/** The outcome of posting a form. */
sealed interface SubmitResult {
    data object Sent : SubmitResult

    data class Failed(val error: FormError) : SubmitResult
}

/** Posts create-only items to Directus with a bearer token (iOS `FeedbackService.createItem`). */
object DirectusForms {
    /**
     * POST [body] as JSON to [path] under [baseUrl] with [token]; null when the build has no
     * Directus URL or token, or the URL isn't one.
     */
    fun createRequest(baseUrl: String?, token: String?, path: String, body: JsonObject): Request? {
        val base = baseUrl?.trim()?.takeIf { it.isNotEmpty() }?.toHttpUrlOrNull() ?: return null
        val bearer = token?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        return Request.Builder()
            .url(base.newBuilder().addPathSegments(path).build())
            .header("Authorization", "Bearer $bearer")
            .header("Accept", "application/json")
            .post(body.toString().toRequestBody(JSON))
            .build()
    }

    /**
     * Sends a request from [createRequest]. Directus answers 200 with the item, or 204 when the
     * token cannot read the collection back, which a create-only one cannot.
     */
    suspend fun send(request: Request?, http: OkHttpClient): SubmitResult {
        request ?: return SubmitResult.Failed(FormError.NotConfigured)
        return withContext(Dispatchers.IO) {
            try {
                http.newCall(request).execute().use { response ->
                    if (response.isSuccessful) {
                        SubmitResult.Sent
                    } else {
                        SubmitResult.Failed(FormError.Server(response.code))
                    }
                }
            } catch (e: UnknownHostException) {
                // No connection: OkHttp can't even look the host up.
                SubmitResult.Failed(FormError.Offline)
            } catch (e: NoRouteToHostException) {
                SubmitResult.Failed(FormError.Offline)
            } catch (e: IOException) {
                SubmitResult.Failed(FormError.Network)
            }
        }
    }

    private val JSON = "application/json".toMediaType()
}
