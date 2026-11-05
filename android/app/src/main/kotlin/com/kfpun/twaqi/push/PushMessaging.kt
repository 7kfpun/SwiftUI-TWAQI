package com.kfpun.twaqi.push

import android.content.Context
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.kfpun.twaqi.BuildConfig

/**
 * FCM's side (iOS `AppDelegate`'s Messaging delegate). Wired only in builds with
 * `app/google-services.json` (`BuildConfig.FCM_ENABLED`, the manifest's `FCM_ENABLED`); without
 * it alerts are still saved on the phone, and there is no token to sync them with.
 */
object PushMessaging {
    val isAvailable: Boolean get() = BuildConfig.FCM_ENABLED

    /** At launch: hands the current FCM token to [PushSync] (it writes the row when it changed). */
    fun start(context: Context) {
        val sync = PushGraph.sync(context)
        sync.start()
        if (!isAvailable || FirebaseApp.getApps(context).isEmpty()) return
        FirebaseMessaging.getInstance().token
            .addOnSuccessListener(sync::fcmTokenChanged)
            .addOnFailureListener { Log.w(TAG, "FCM token unavailable: ${it.message}") }
    }

    private const val TAG = "PushMessaging"
}

/**
 * Token rotation and alerts that arrive while the app is open. With the app in the background
 * Android shows the sender's notification itself, on [AlertNotifications.CHANNEL_ID].
 */
class TwaqiMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        PushGraph.sync(this).fcmTokenChanged(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val notification = message.notification
        AlertNotifications.show(this, AlertMessage.from(notification?.title, notification?.body, message.data))
    }
}
