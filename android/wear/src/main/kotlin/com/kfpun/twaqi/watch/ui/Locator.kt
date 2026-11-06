package com.kfpun.twaqi.watch.ui

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull

/** One-shot, coarse location for picking the home station (iOS `Locator`). Never asks for permission itself. */
class Locator(private val context: Context) {
    fun hasPermission(): Boolean =
        context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    /** Null when the reader declined, or no fix arrives in time. */
    @SuppressLint("MissingPermission") // Checked by hasPermission() first.
    suspend fun current(): Location? {
        if (!hasPermission()) return null
        val manager = context.getSystemService(LocationManager::class.java) ?: return null
        // A station is several kilometres from the next; a coarse fix is faster and kinder to the battery.
        val providers = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) add(LocationManager.FUSED_PROVIDER)
            add(LocationManager.NETWORK_PROVIDER)
            add(LocationManager.GPS_PROVIDER)
        }.filter { runCatching { manager.isProviderEnabled(it) }.getOrDefault(false) }
        val lastKnown = providers.firstNotNullOfOrNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }
        val provider = providers.firstOrNull() ?: return lastKnown
        val fresh = withTimeoutOrNull(TIMEOUT_MILLIS) {
            suspendCancellableCoroutine { continuation ->
                val signal = CancellationSignal()
                continuation.invokeOnCancellation { signal.cancel() }
                manager.getCurrentLocation(provider, signal, context.mainExecutor) { continuation.resume(it) }
            }
        }
        return fresh ?: lastKnown
    }

    private companion object {
        const val TIMEOUT_MILLIS = 10_000L
    }
}
