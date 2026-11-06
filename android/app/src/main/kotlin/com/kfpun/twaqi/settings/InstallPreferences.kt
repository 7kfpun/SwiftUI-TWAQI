package com.kfpun.twaqi.settings

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import java.util.UUID

/**
 * Values that belong to this install only: the analytics opt-out (FOX-60) and the anonymous id
 * sent with feedback. The file is left out of backups (`backup_rules.xml`,
 * `data_extraction_rules.xml`), so a new phone starts fresh, as iOS's per-vendor id does.
 */
object InstallPreferences {
    /** `shared_prefs/install.xml`. */
    const val FILE = "install"

    private const val KEY_ANONYMOUS_ID = "anonymous_id"

    fun get(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /** A random id for this install, made on first use (iOS `identifierForVendor`). */
    @Synchronized
    fun anonymousId(context: Context): String {
        val preferences = get(context)
        preferences.getString(KEY_ANONYMOUS_ID, null)?.let { return it }
        return UUID.randomUUID().toString().uppercase().also { id ->
            preferences.edit { putString(KEY_ANONYMOUS_ID, id) }
        }
    }
}
