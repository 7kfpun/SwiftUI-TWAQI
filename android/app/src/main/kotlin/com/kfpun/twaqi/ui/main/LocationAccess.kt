package com.kfpun.twaqi.ui.main

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import androidx.core.util.Consumer

/**
 * The reader's location through the platform's LocationManager, once the runtime permission is
 * given. Coarse is enough: the map's blue dot, "my location" and the nearest sort.
 */
object LocationAccess {
    val permissions = arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)

    fun isGranted(context: Context): Boolean = permissions.any {
        ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
    }

    /** The newest fix any provider has, without waiting; null without the permission. */
    @SuppressLint("MissingPermission") // Checked by isGranted.
    fun lastKnown(context: Context): GeoPoint? {
        if (!isGranted(context)) return null
        val manager = context.getSystemService(LocationManager::class.java) ?: return null
        return manager.getProviders(true)
            .mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }
            .maxByOrNull(Location::getTime)
            ?.let { GeoPoint(it.latitude, it.longitude) }
    }

    /** A fresh fix, or the last known one when no provider answers; null without the permission. */
    @SuppressLint("MissingPermission") // Checked by isGranted.
    fun current(context: Context, onResult: (GeoPoint?) -> Unit) {
        if (!isGranted(context)) return onResult(null)
        val manager = context.getSystemService(LocationManager::class.java) ?: return onResult(null)
        val provider = listOfNotNull(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) LocationManager.FUSED_PROVIDER else null,
            LocationManager.NETWORK_PROVIDER,
            LocationManager.GPS_PROVIDER
        ).firstOrNull { runCatching { manager.isProviderEnabled(it) }.getOrDefault(false) }
            ?: return onResult(lastKnown(context))
        val noCancel: CancellationSignal? = null
        val callback = Consumer<Location?> { location ->
            onResult(location?.let { GeoPoint(it.latitude, it.longitude) } ?: lastKnown(context))
        }
        LocationManagerCompat.getCurrentLocation(
            manager,
            provider,
            noCancel,
            ContextCompat.getMainExecutor(context),
            callback
        )
    }
}
