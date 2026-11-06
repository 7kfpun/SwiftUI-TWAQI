package com.kfpun.twaqi.push

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import java.time.Instant
import java.time.LocalTime
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Help's do-not-disturb window (iOS `SettingsStore.isDndEnabled`, `dndStartTime`, `dndEndTime`).
 * The sender skips alerts inside it, in the phone's time zone.
 */
data class DndWindow(val enabled: Boolean, val start: LocalTime, val end: LocalTime) {
    companion object {
        /** iOS registers "now" to "now + 2 h" at first launch; Android starts from a fixed night window. */
        val DEFAULT = DndWindow(enabled = false, start = LocalTime.of(22, 0), end = LocalTime.of(7, 0))
    }
}

/**
 * Where the push settings are kept on the phone (iOS `DirectusPushMirror`'s `UserDefaults` keys).
 *
 * Two kinds of state: what the user set ([wanted], [siteIds], [dnd]), which Android backup
 * carries to a new phone or a reinstall, and the sync bookkeeping (everything else), which
 * belongs to this install's device row and is left out of backups, as are the identity's id
 * and secret ([PushIdentity]).
 */
interface PushStore {
    /** Station id → alerts as the user set them (or as restored), written to the push API or not. */
    var wanted: Map<String, StationAlerts>
    var siteIds: Map<String, String>
    var dnd: DndWindow

    /** Station id → alerts as last written to (or read from) the push API. */
    var synced: Map<String, StationAlerts>

    /** This install's row id, once it has one. */
    var deviceRowId: Int?

    /** The latest FCM token Messaging gave, and the one last written to the row. */
    var fcmToken: String?
    var syncedFcmToken: String?

    /** The `device_token` and `PushDevicePayload.profile` last written. */
    var syncedDeviceToken: String?
    var syncedProfile: String?
    var lastDeviceSyncAt: Instant?

    /** The user changed do-not-disturb on this install: a restore never overwrites it. */
    var dndEdited: Boolean

    /** Help's "cancel all" is still to reach the push API. */
    var archiveAll: Boolean

    /** This install has looked for a row an earlier install left. */
    var restored: Boolean

    /** Android 13+: the notification permission was asked for at least once. */
    var notificationsAsked: Boolean
}

/** In memory: for tests and previews. */
class InMemoryPushStore : PushStore {
    override var wanted: Map<String, StationAlerts> = emptyMap()
    override var siteIds: Map<String, String> = emptyMap()
    override var dnd: DndWindow = DndWindow.DEFAULT
    override var synced: Map<String, StationAlerts> = emptyMap()
    override var deviceRowId: Int? = null
    override var fcmToken: String? = null
    override var syncedFcmToken: String? = null
    override var syncedDeviceToken: String? = null
    override var syncedProfile: String? = null
    override var lastDeviceSyncAt: Instant? = null
    override var dndEdited: Boolean = false
    override var archiveAll: Boolean = false
    override var restored: Boolean = false
    override var notificationsAsked: Boolean = false
}

/**
 * Shared preferences: [SETTINGS_PREFS] is backed up (the user's alerts and quiet hours, as iOS
 * keeps them in its defaults); [SYNC_PREFS] is excluded in `backup_rules.xml` and
 * `data_extraction_rules.xml`, so a restored phone registers its own row and writes the
 * restored alerts to it.
 */
class SharedPreferencesPushStore(context: Context) : PushStore {
    private val settings: SharedPreferences = context.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
    private val sync: SharedPreferences = context.getSharedPreferences(SYNC_PREFS, Context.MODE_PRIVATE)

    override var wanted: Map<String, StationAlerts>
        get() = StationAlerts.decodeMap(settings.getString(KEY_WANTED, null))
        set(value) = settings.edit { putString(KEY_WANTED, StationAlerts.encodeMap(value)) }

    override var siteIds: Map<String, String>
        get() = decodeStrings(settings.getString(KEY_SITE_IDS, null))
        set(
            value
        ) = settings.edit {
            putString(KEY_SITE_IDS, JsonObject(value.mapValues { JsonPrimitive(it.value) }).toString())
        }

    override var dnd: DndWindow
        get() = DndWindow(
            enabled = settings.getBoolean(KEY_DND_ENABLED, DndWindow.DEFAULT.enabled),
            start = minutes(settings.getInt(KEY_DND_START, -1)) ?: DndWindow.DEFAULT.start,
            end = minutes(settings.getInt(KEY_DND_END, -1)) ?: DndWindow.DEFAULT.end
        )
        set(value) = settings.edit {
            putBoolean(KEY_DND_ENABLED, value.enabled)
            putInt(KEY_DND_START, value.start.hour * 60 + value.start.minute)
            putInt(KEY_DND_END, value.end.hour * 60 + value.end.minute)
        }

    override var synced: Map<String, StationAlerts>
        get() = StationAlerts.decodeMap(sync.getString(KEY_SYNCED, null))
        set(value) = sync.edit { putString(KEY_SYNCED, StationAlerts.encodeMap(value)) }

    override var deviceRowId: Int?
        get() = if (sync.contains(KEY_DEVICE_ROW)) sync.getInt(KEY_DEVICE_ROW, 0) else null
        set(value) = sync.edit { if (value == null) remove(KEY_DEVICE_ROW) else putInt(KEY_DEVICE_ROW, value) }

    override var fcmToken: String? by syncString(KEY_FCM_TOKEN)
    override var syncedFcmToken: String? by syncString(KEY_SYNCED_FCM_TOKEN)
    override var syncedDeviceToken: String? by syncString(KEY_SYNCED_DEVICE_TOKEN)
    override var syncedProfile: String? by syncString(KEY_PROFILE)

    override var lastDeviceSyncAt: Instant?
        get() = if (sync.contains(KEY_LAST_SYNC)) Instant.ofEpochMilli(sync.getLong(KEY_LAST_SYNC, 0)) else null
        set(value) = sync.edit {
            if (value ==
                null
            ) {
                remove(KEY_LAST_SYNC)
            } else {
                putLong(KEY_LAST_SYNC, value.toEpochMilli())
            }
        }

    override var dndEdited: Boolean by syncFlag(KEY_DND_EDITED)
    override var archiveAll: Boolean by syncFlag(KEY_ARCHIVE_ALL)
    override var restored: Boolean by syncFlag(KEY_RESTORED)
    override var notificationsAsked: Boolean by syncFlag(KEY_NOTIFICATIONS_ASKED)

    private fun syncString(key: String) = object : kotlin.properties.ReadWriteProperty<Any?, String?> {
        override fun getValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>): String? = sync.getString(key, null)

        override fun setValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>, value: String?) =
            sync.edit { if (value == null) remove(key) else putString(key, value) }
    }

    private fun syncFlag(key: String) = object : kotlin.properties.ReadWriteProperty<Any?, Boolean> {
        override fun getValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>): Boolean =
            sync.getBoolean(key, false)

        override fun setValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>, value: Boolean) =
            sync.edit { putBoolean(key, value) }
    }

    companion object {
        /** Backed up: the alerts and quiet hours the user set. */
        const val SETTINGS_PREFS = "push_settings"

        /** Not backed up: this install's sync bookkeeping. */
        const val SYNC_PREFS = "push_sync"

        // Same names as iOS DirectusPushMirror.Keys and SettingsStore where there is one.
        private const val KEY_WANTED = "directusPushWantedAlerts"
        private const val KEY_SITE_IDS = "directusPushSiteIds"
        private const val KEY_DND_ENABLED = "dndEnabled"
        private const val KEY_DND_START = "dndStartMinutes"
        private const val KEY_DND_END = "dndEndMinutes"
        private const val KEY_SYNCED = "directusPushSyncedAlerts"
        private const val KEY_DEVICE_ROW = "directusPushDeviceId"
        private const val KEY_FCM_TOKEN = "pushFcmToken"
        private const val KEY_SYNCED_FCM_TOKEN = "directusPushFcmToken"
        private const val KEY_SYNCED_DEVICE_TOKEN = "directusPushDeviceToken"
        private const val KEY_PROFILE = "directusPushDeviceProfile"
        private const val KEY_LAST_SYNC = "directusPushLastDeviceSyncAt"
        private const val KEY_DND_EDITED = "directusPushDndEditedLocally"
        private const val KEY_ARCHIVE_ALL = "directusPushArchiveAll"
        private const val KEY_RESTORED = "directusPushRestored"
        private const val KEY_NOTIFICATIONS_ASKED = "pushNotificationsAsked"

        private fun minutes(value: Int): LocalTime? = if (value in
            0 until 24 * 60
        ) {
            LocalTime.of(value / 60, value % 60)
        } else {
            null
        }

        private fun decodeStrings(text: String?): Map<String, String> {
            if (text.isNullOrBlank()) return emptyMap()
            return runCatching {
                Json.parseToJsonElement(text).jsonObject.mapNotNull { (key, value) ->
                    value.jsonPrimitive.contentOrNull?.let { key to it }
                }.toMap()
            }.getOrDefault(emptyMap())
        }
    }
}
