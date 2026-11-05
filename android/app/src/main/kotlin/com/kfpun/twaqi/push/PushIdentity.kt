package com.kfpun.twaqi.push

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import androidx.core.content.edit
import java.security.GeneralSecurityException
import java.security.KeyStore
import java.security.SecureRandom
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * This install's id and secret for the push API (iOS `PushDeviceIdentity`, FOX-37 M5). The
 * Worker stores only a hash of the secret, and serves each request only the rows of the device
 * it names.
 */
interface PushIdentity {
    /** The stored id (a lowercase UUID), made on first use. Null only if the Keystore refuses. */
    fun id(): String?

    /** 32 random bytes, base64url, made on first use. Null only if the Keystore refuses. */
    fun secret(): String?

    /** Forgets both, so the next use makes new ones: after the push API refused them (403). */
    fun reset()

    companion object {
        fun newId(): String = UUID.randomUUID().toString().lowercase()

        fun newSecret(random: SecureRandom = SecureRandom()): String = base64url(ByteArray(32).also(random::nextBytes))

        /** Base64url without padding, as iOS `PushDeviceIdentity.base64url`. */
        fun base64url(bytes: ByteArray): String =
            java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    }
}

/**
 * The id and secret encrypted with an AES-GCM key held in the Android Keystore, in shared
 * preferences left out of backups. Android removes Keystore keys on uninstall, so unlike the iOS
 * Keychain a reinstall starts with a new identity and a new row; the alerts themselves come back
 * from backup and are written to it. A copy restored without its key can't be read and is
 * replaced.
 */
class KeystorePushIdentity(context: Context) : PushIdentity {
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    @Synchronized
    override fun id(): String? = value(KEY_ID, PushIdentity::newId)

    @Synchronized
    override fun secret(): String? = value(KEY_SECRET) { PushIdentity.newSecret() }

    @Synchronized
    override fun reset() {
        prefs.edit {
            remove(KEY_ID)
            remove(KEY_SECRET)
        }
    }

    private fun value(key: String, make: () -> String): String? = try {
        read(key) ?: make().also { write(key, it) }
    } catch (e: GeneralSecurityException) {
        Log.w(TAG, "Keystore refused the push identity", e)
        null
    }

    private fun read(key: String): String? {
        val stored = prefs.getString(key, null) ?: return null
        return try {
            val bytes = Base64.decode(stored, Base64.NO_WRAP)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes, 0, IV_SIZE))
            String(cipher.doFinal(bytes, IV_SIZE, bytes.size - IV_SIZE), Charsets.UTF_8).takeIf(String::isNotEmpty)
        } catch (e: GeneralSecurityException) {
            // Not this key's (restored from elsewhere, or the key was lost): start again.
            Log.w(TAG, "Push identity unreadable; making a new one", e)
            prefs.edit { remove(key) }
            null
        } catch (e: IllegalArgumentException) {
            prefs.edit { remove(key) }
            null
        }
    }

    private fun write(key: String, value: String) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val sealed = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        prefs.edit { putString(key, Base64.encodeToString(sealed, Base64.NO_WRAP)) }
    }

    private fun key(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    companion object {
        /** Left out of backups (`backup_rules.xml`, `data_extraction_rules.xml`). */
        const val PREFS = "push_identity"
        private const val KEY_ID = "directusDeviceId"
        private const val KEY_SECRET = "pushDeviceSecret"
        private const val KEY_ALIAS = "com.kfpun.twaqi.push"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val IV_SIZE = 12
        private const val TAG = "PushIdentity"
    }
}
