package com.kfpun.twaqi.ads

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.ads.MobileAds
import com.google.android.ump.ConsentDebugSettings
import com.google.android.ump.ConsentInformation
import com.google.android.ump.ConsentInformation.PrivacyOptionsRequirementStatus
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.UserMessagingPlatform
import com.kfpun.twaqi.BuildConfig
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Google's User Messaging Platform consent (EEA, UK and other regions where it
 * applies), then AdMob. Nothing requests an ad until [canRequestAds].
 */
object AdConsent {
    private val canRequest = MutableStateFlow(false)
    val canRequestAds: StateFlow<Boolean> = canRequest.asStateFlow()

    private val privacyOptions = MutableStateFlow(false)

    /**
     * True where the user must be able to change their choice: Help shows a "Privacy settings" row
     * (FOX-116) that opens [showPrivacyOptions].
     */
    val privacyOptionsRequired: StateFlow<Boolean> = privacyOptions.asStateFlow()

    private val adsStarted = AtomicBoolean(false)

    /** Debug builds only: UMP's test geography, so the consent form and privacy row show anywhere. */
    @Volatile
    private var debugSettings: ConsentDebugSettings? = null

    /**
     * FOX-116: Help shows the row only where UMP says a privacy options entry point is required;
     * not where it isn't, nor before UMP has answered.
     */
    fun showsPrivacyOptions(status: PrivacyOptionsRequirementStatus?): Boolean =
        status == PrivacyOptionsRequirementStatus.REQUIRED

    /**
     * At every launch, for free and Pro users alike: whether the privacy row shows, from the answer
     * UMP kept from an earlier launch. Pro users never [gather], but keep the row while UMP still
     * requires it (FOX-116). Only a read of what UMP stored; [gather] is what asks UMP again (free
     * users), and it updates the row too.
     */
    fun restore(context: Context) {
        privacyOptions.value = showsPrivacyOptions(
            UserMessagingPlatform.getConsentInformation(context).privacyOptionsRequirementStatus
        )
    }

    /**
     * Debug builds started with `--ez ump_debug_eea true` (and `--es ump_test_device <hashed id>`,
     * which UMP logs on first use) act as if in the EEA, for testing the consent form and the
     * privacy row. `--ez ump_reset true` forgets the choice made. Release builds ignore them.
     * Read only when MainActivity is created, so test from a cold start (`am force-stop` first): a
     * running app gets later intents in `onNewIntent`, which leaves these alone.
     */
    fun useDebugSettings(context: Context, intent: Intent) {
        if (!BuildConfig.DEBUG) return
        if (intent.getBooleanExtra(EXTRA_DEBUG_RESET, false)) {
            UserMessagingPlatform.getConsentInformation(context).reset()
        }
        if (!intent.getBooleanExtra(EXTRA_DEBUG_EEA, false)) return
        debugSettings = ConsentDebugSettings.Builder(context)
            .setDebugGeography(ConsentDebugSettings.DebugGeography.DEBUG_GEOGRAPHY_EEA)
            .apply { intent.getStringExtra(EXTRA_DEBUG_TEST_DEVICE)?.let(::addTestDeviceHashedId) }
            .build()
    }

    /** Every launch, for free users: refreshes consent and shows the form when one is needed. */
    fun gather(activity: Activity) {
        val info = UserMessagingPlatform.getConsentInformation(activity)
        val parameters = ConsentRequestParameters.Builder()
            .apply { debugSettings?.let(::setConsentDebugSettings) }
            .build()
        info.requestConsentInfoUpdate(
            activity,
            parameters,
            {
                UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity) { error ->
                    error?.let { Log.w(TAG, "Consent form: ${it.message}") }
                    update(activity, info)
                }
            },
            { error ->
                Log.w(TAG, "Consent update: ${error.message}")
                update(activity, info)
            }
        )
        // A choice from an earlier launch lets ads load now, before the update returns.
        update(activity, info)
    }

    /** Help › Privacy settings (FOX-116): UMP's form to change the consent choice. */
    fun showPrivacyOptions(activity: Activity) {
        UserMessagingPlatform.showPrivacyOptionsForm(activity) { error ->
            error?.let { Log.w(TAG, "Privacy options: ${it.message}") }
            update(activity, UserMessagingPlatform.getConsentInformation(activity))
        }
    }

    private fun update(context: Context, info: ConsentInformation) {
        privacyOptions.value = showsPrivacyOptions(info.privacyOptionsRequirementStatus)
        if (!info.canRequestAds()) return
        if (adsStarted.compareAndSet(false, true)) MobileAds.initialize(context.applicationContext)
        canRequest.value = true
    }

    const val EXTRA_DEBUG_EEA = "ump_debug_eea"
    const val EXTRA_DEBUG_TEST_DEVICE = "ump_test_device"
    const val EXTRA_DEBUG_RESET = "ump_reset"

    private const val TAG = "TWAQIAds"
}
