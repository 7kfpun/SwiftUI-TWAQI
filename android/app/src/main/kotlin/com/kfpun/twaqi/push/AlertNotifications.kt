package com.kfpun.twaqi.push

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.kfpun.twaqi.MainActivity
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.locale.AppLocale

/** One alert as FCM delivers it: the sender's text (in the device row's language) and its data. */
data class AlertMessage(
    val title: String?,
    val body: String?,
    val stationId: Int?,
    val subscriptionId: String?,
    val direction: PushDirection?,
    val threshold: Int?,
    val aqi: Int?
) {
    companion object {
        /** From the FCM data the Worker sends (`station_id`, `subscription_id`, `direction`, `threshold`, `aqi`). */
        fun from(title: String?, body: String?, data: Map<String, String>) = AlertMessage(
            title = title,
            body = body,
            stationId = data["station_id"]?.toIntOrNull(),
            subscriptionId = data["subscription_id"],
            direction = PushDirection.fromWire(data["direction"]),
            threshold = data["threshold"]?.toIntOrNull(),
            aqi = data["aqi"]?.toIntOrNull()
        )
    }
}

/**
 * The alerts' notification channel and the notifications themselves. Text the app writes here
 * (the channel, and an alert that comes without the sender's text) uses the app language
 * through [AppLocale.localizedContext], not the phone's (FOX-56).
 */
object AlertNotifications {
    /** Also the FCM default channel (manifest), for alerts Android shows while the app is in the background. */
    const val CHANNEL_ID = "aqi_alerts"

    /** The station to open, on the intent a tapped alert starts MainActivity with (FCM puts data keys there as extras). */
    const val EXTRA_STATION_ID = "station_id"

    /** Creates or renames the channel in the app language. Call at start and after a language change. */
    fun ensureChannel(context: Context) {
        val localized = AppLocale.localizedContext(context)
        val channel = NotificationChannel(
            CHANNEL_ID,
            localized.getString(R.string.push_channel_alerts_name),
            NotificationManager.IMPORTANCE_HIGH
        ).apply { description = localized.getString(R.string.push_channel_alerts_description) }
        context.getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }

    /** The title and text for [message]: the sender's own, else written here from its data. */
    fun text(context: Context, message: AlertMessage, stationName: String? = null): Pair<String, String>? {
        if (!message.title.isNullOrBlank() && !message.body.isNullOrBlank()) return message.title to message.body
        val direction = message.direction ?: return null
        val aqi = message.aqi ?: return null
        val threshold = message.threshold ?: return null
        val localized = AppLocale.localizedContext(context)
        val name = stationName ?: "#${message.stationId ?: "?"}"
        val title = localized.getString(R.string.push_alert_title, name, aqi)
        val body = when (direction) {
            PushDirection.ABOVE -> localized.getString(R.string.push_alert_above_body, threshold)
            PushDirection.BELOW -> localized.getString(R.string.push_alert_below_body, threshold)
        }
        return title to body
    }

    /**
     * Shows [message] (an alert that arrived with the app open, or one posted locally). Tapping it
     * opens the station. Nothing when notifications are off or the permission isn't granted.
     */
    fun show(context: Context, message: AlertMessage, stationName: String? = null): Boolean {
        val (title, body) = text(context, message, stationName) ?: return false
        if (!canPost(context)) return false
        ensureChannel(context)
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
            .apply { message.stationId?.let { putExtra(EXTRA_STATION_ID, it.toString()) } }
        val requestCode = message.stationId ?: 0
        val pending = PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        // The reading's band colour, as on the station page.
        val status = message.aqi?.let { AirStatus.of(AirIndexType.AQI, it.toDouble()) } ?: AirStatus.UNKNOWN
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(0xFF000000.toInt() or status.color)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setAutoCancel(true)
            .setContentIntent(pending)
            // A station's alerts group together, as iOS threads them.
            .setGroup("station-${message.stationId}")
            .build()
        // Same tag replaces an earlier alert still showing (the sender's collapse id).
        val tag = message.subscriptionId?.let { "aqi-$it" } ?: "station-${message.stationId}"
        @Suppress("MissingPermission") // canPost checked it.
        NotificationManagerCompat.from(context).notify(tag, NOTIFICATION_ID, notification)
        return true
    }

    /** Debug builds' sample alert (MainActivity's `demo_alert`): Keelung above 100, in the app language. */
    fun demo(context: Context): AlertMessage {
        val message =
            AlertMessage(
                null,
                null,
                stationId = 91,
                subscriptionId = null,
                direction = PushDirection.ABOVE,
                threshold = 100,
                aqi = 123
            )
        val name = if (AppLocale.isChinese(context)) "基隆" else "Keelung"
        val (title, body) = text(context, message, name) ?: return message
        return message.copy(title = title, body = body)
    }

    fun canPost(context: Context): Boolean {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    /** The station a tapped alert asks to open, from its intent's extras. */
    fun stationId(intent: Intent?): Int? = intent?.getStringExtra(EXTRA_STATION_ID)?.toIntOrNull()

    private const val NOTIFICATION_ID = 1
}
