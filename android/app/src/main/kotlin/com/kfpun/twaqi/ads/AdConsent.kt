package com.kfpun.twaqi.ads

import android.app.Activity
import android.content.Context
import android.util.Log
import com.google.android.gms.ads.MobileAds
import com.google.android.ump.ConsentInformation
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.UserMessagingPlatform
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

    /** True where the user must be able to change their choice: settings shows a "Privacy options" row. */
    val privacyOptionsRequired: StateFlow<Boolean> = privacyOptions.asStateFlow()

    private val adsStarted = AtomicBoolean(false)

    /** Every launch, for free users: refreshes consent and shows the form when one is needed. */
    fun gather(activity: Activity) {
        val info = UserMessagingPlatform.getConsentInformation(activity)
        info.requestConsentInfoUpdate(
            activity,
            ConsentRequestParameters.Builder().build(),
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

    fun showPrivacyOptions(activity: Activity) {
        UserMessagingPlatform.showPrivacyOptionsForm(activity) { error ->
            error?.let { Log.w(TAG, "Privacy options: ${it.message}") }
            update(activity, UserMessagingPlatform.getConsentInformation(activity))
        }
    }

    private fun update(context: Context, info: ConsentInformation) {
        privacyOptions.value =
            info.privacyOptionsRequirementStatus == ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED
        if (!info.canRequestAds()) return
        if (adsStarted.compareAndSet(false, true)) MobileAds.initialize(context.applicationContext)
        canRequest.value = true
    }

    private const val TAG = "TWAQIAds"
}
