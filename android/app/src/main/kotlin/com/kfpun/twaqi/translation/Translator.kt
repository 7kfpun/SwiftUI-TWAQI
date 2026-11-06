package com.kfpun.twaqi.translation

import android.content.Context
import android.net.ConnectivityManager
import com.google.android.gms.tasks.Task
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.TranslateRemoteModel
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.TranslatorOptions
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine

/** Translates Traditional Chinese text on the device. Behind an interface so tests never load ML Kit. */
fun interface Translator {
    /**
     * [texts] translated into [target] ("en"), by original. Whatever could not be translated is
     * left out, and an empty map means nothing could be (no model, offline, an error).
     */
    suspend fun translate(texts: List<String>, target: String): Map<String, String>
}

/**
 * ML Kit's on-device translation, Chinese → [target] (free, no key, runs offline once the model
 * is on the device).
 *
 * The model (about 30 MB) is downloaded on first use, and only on an unmetered network
 * ([canDownload], Wi-Fi in practice), so a reader on mobile data is never charged for it; until
 * then the original Chinese shows. iOS has no download step of its own: Apple's Translation uses
 * the language packs already on the device and never prompts for one, so the original shows there
 * too until the pack is installed.
 */
class MlKitTranslator(private val canDownload: () -> Boolean) : Translator {
    private val clients = mutableMapOf<String, com.google.mlkit.nl.translate.Translator>()

    override suspend fun translate(texts: List<String>, target: String): Map<String, String> {
        val language = TranslateLanguage.fromLanguageTag(target) ?: return emptyMap()
        val client = client(language)
        if (!modelReady(language)) {
            if (!canDownload()) return emptyMap()
            val downloaded = runCatching {
                client.downloadModelIfNeeded(DownloadConditions.Builder().build()).awaitResult()
            }
            if (downloaded.isFailure) return emptyMap()
        }
        val results = LinkedHashMap<String, String>()
        for (text in texts) {
            val translation = runCatching { client.translate(text).awaitResult() }.getOrNull() ?: continue
            results[text] = translation
        }
        return results
    }

    @Synchronized
    private fun client(target: String) = clients.getOrPut(target) {
        Translation.getClient(
            TranslatorOptions.Builder()
                .setSourceLanguage(TranslateLanguage.CHINESE)
                .setTargetLanguage(target)
                .build()
        )
    }

    /** Both ends' models are on the device (English ships with ML Kit, Chinese is downloaded). */
    private suspend fun modelReady(target: String): Boolean = runCatching {
        val manager = RemoteModelManager.getInstance()
        listOf(TranslateLanguage.CHINESE, target).all { language ->
            manager.isModelDownloaded(TranslateRemoteModel.Builder(language).build()).awaitResult()
        }
    }.getOrDefault(false)

    companion object {
        /** The rule [MlKitTranslator] downloads by: the active network is not metered (Wi-Fi, Ethernet). */
        fun unmeteredNetwork(context: Context): () -> Boolean {
            val app = context.applicationContext
            return {
                val manager = app.getSystemService(ConnectivityManager::class.java)
                manager != null && manager.activeNetwork != null && !manager.isActiveNetworkMetered
            }
        }
    }
}

/** A Play services [Task]'s result, suspending until it completes. */
private suspend fun <T> Task<T>.awaitResult(): T = suspendCancellableCoroutine { continuation ->
    addOnSuccessListener { continuation.resume(it) }
    addOnFailureListener { continuation.resumeWithException(it) }
    addOnCanceledListener { continuation.cancel() }
}
