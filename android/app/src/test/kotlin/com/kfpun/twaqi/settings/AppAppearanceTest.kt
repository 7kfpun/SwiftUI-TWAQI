package com.kfpun.twaqi.settings

import android.content.SharedPreferences
import androidx.appcompat.app.AppCompatDelegate
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/** iOS `AppAppearanceTests` (FOX-43): light, dark or system look, chosen under Help. */
class AppAppearanceTest {
    private val prefs = FakePreferences()

    @After
    fun tearDown() {
        AppCompatDelegate.setDefaultNightMode(AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
    }

    @Test
    fun followsSystemUntilChosen() {
        assertEquals(AppAppearance.SYSTEM, AppAppearanceStore.read(prefs))
    }

    @Test
    fun unknownStoredValueFollowsSystem() {
        prefs.edit().putString(AppAppearanceStore.KEY, "sepia").apply()

        assertEquals(AppAppearance.SYSTEM, AppAppearanceStore.read(prefs))
    }

    @Test
    fun choiceIsStoredAndSystemRemovesIt() {
        AppAppearanceStore.write(prefs, AppAppearance.DARK)
        assertEquals("dark", prefs.getString(AppAppearanceStore.KEY, null))
        assertEquals(AppAppearance.DARK, AppAppearanceStore.read(prefs))

        AppAppearanceStore.write(prefs, AppAppearance.LIGHT)
        assertEquals(AppAppearance.LIGHT, AppAppearanceStore.read(prefs))

        AppAppearanceStore.write(prefs, AppAppearance.SYSTEM)
        assertFalse(prefs.contains(AppAppearanceStore.KEY))
        assertEquals(AppAppearance.SYSTEM, AppAppearanceStore.read(prefs))
    }

    @Test
    fun idsMatchIos() {
        assertEquals(listOf("system", "light", "dark"), AppAppearance.entries.map { it.id })
        assertEquals("appAppearance", AppAppearanceStore.KEY)
    }

    @Test
    fun nightModeForEachChoice() {
        assertEquals(AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM, AppAppearance.SYSTEM.nightMode)
        assertEquals(AppCompatDelegate.MODE_NIGHT_NO, AppAppearance.LIGHT.nightMode)
        assertEquals(AppCompatDelegate.MODE_NIGHT_YES, AppAppearance.DARK.nightMode)
    }

    @Test
    fun applySetsTheAppNightModeAndSystemClearsTheOverride() {
        AppAppearanceStore.apply(AppAppearance.DARK)
        assertEquals(AppCompatDelegate.MODE_NIGHT_YES, AppCompatDelegate.getDefaultNightMode())

        AppAppearanceStore.apply(AppAppearance.LIGHT)
        assertEquals(AppCompatDelegate.MODE_NIGHT_NO, AppCompatDelegate.getDefaultNightMode())

        AppAppearanceStore.apply(AppAppearance.SYSTEM)
        assertEquals(AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM, AppCompatDelegate.getDefaultNightMode())
    }
}

/** In-memory [SharedPreferences] for JVM tests. */
private class FakePreferences : SharedPreferences {
    private val values = mutableMapOf<String, Any?>()

    override fun getAll(): Map<String, *> = values.toMap()

    override fun getString(key: String, defValue: String?): String? = values[key] as? String ?: defValue

    @Suppress("UNCHECKED_CAST")
    override fun getStringSet(key: String, defValues: Set<String>?): Set<String>? =
        values[key] as? Set<String> ?: defValues

    override fun getInt(key: String, defValue: Int): Int = values[key] as? Int ?: defValue

    override fun getLong(key: String, defValue: Long): Long = values[key] as? Long ?: defValue

    override fun getFloat(key: String, defValue: Float): Float = values[key] as? Float ?: defValue

    override fun getBoolean(key: String, defValue: Boolean): Boolean = values[key] as? Boolean ?: defValue

    override fun contains(key: String): Boolean = key in values

    override fun edit(): SharedPreferences.Editor = Editor()

    override fun registerOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener
    ) {}

    override fun unregisterOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener
    ) {}

    private inner class Editor : SharedPreferences.Editor {
        private val changes = mutableMapOf<String, Any?>()
        private val removals = mutableSetOf<String>()
        private var clear = false

        override fun putString(key: String, value: String?) = apply { changes[key] = value }

        override fun putStringSet(key: String, values: Set<String>?) = apply { changes[key] = values }

        override fun putInt(key: String, value: Int) = apply { changes[key] = value }

        override fun putLong(key: String, value: Long) = apply { changes[key] = value }

        override fun putFloat(key: String, value: Float) = apply { changes[key] = value }

        override fun putBoolean(key: String, value: Boolean) = apply { changes[key] = value }

        override fun remove(key: String) = apply { removals += key }

        override fun clear() = apply { clear = true }

        override fun commit(): Boolean {
            if (clear) values.clear()
            removals.forEach { values.remove(it) }
            values.putAll(changes)
            return true
        }

        override fun apply() {
            commit()
        }
    }
}
