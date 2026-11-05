package com.kfpun.twaqi.push

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.kfpun.twaqi.BuildConfig
import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.locale.AppLanguage
import com.kfpun.twaqi.locale.AppLocale
import com.kfpun.twaqi.pro.Entitlement
import com.kfpun.twaqi.pro.ProGraph
import java.util.Locale
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull

/**
 * The app-wide push instances: [PushSync] (the alerts store and its sync), [FavouriteAlerts]
 * and the FCM hook. Like `ProGraph`, built on first use from any component (an activity, the
 * sync worker, the FCM service).
 */
object PushGraph {
    class Instances(val sync: PushSync, val favouriteAlerts: FavouriteAlerts, val logger: EventLogger)

    @Volatile
    private var instances: Instances? = null

    /**
     * The favourites list alerts keep in step. Until FOX-55's `FavouritesRepository` lands it is
     * read and written in the same shared preferences that repository uses; FOX-55's wiring then
     * replaces this with the repository itself (see [PreferencesFavouriteStations]).
     */
    @Volatile
    var favourites: ((Context) -> FavouriteStations)? = null

    fun get(context: Context): Instances = instances ?: synchronized(this) {
        instances ?: build(context.applicationContext).also { instances = it }
    }

    fun sync(context: Context): PushSync = get(context).sync

    fun favouriteAlerts(context: Context): FavouriteAlerts = get(context).favouriteAlerts

    private fun build(context: Context): Instances {
        val logger = EventLogger { name, parameters -> Analytics.logEvent(context, name, parameters) }
        val store = SharedPreferencesPushStore(context)
        val sync = PushSync(
            store = store,
            identity = KeystorePushIdentity(context),
            baseUrl = BuildConfig.PUSH_API_URL,
            apiFactory = { OkHttpPushApi(it) },
            profile = AppDeviceProfile(context, store),
            scheduler = WorkManagerSyncScheduler(context)
        )
        val alerts = FavouriteAlerts(
            store = sync,
            favourites = { (favourites ?: ::PreferencesFavouriteStations)(context) },
            notificationsDenied = { !NotificationManagerCompat.from(context).areNotificationsEnabled() },
            logger = logger,
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        )
        sync.onRestored = alerts::restored
        return Instances(sync, alerts, logger)
    }
}

/** The device row's profile from the app: Pro (FOX-58), the app language (FOX-56) and the notification setting. */
class AppDeviceProfile(private val context: Context, private val store: PushStore) : DeviceProfileSource {
    override suspend fun isPro(): Boolean {
        val entitlement = ProGraph.repository(context).entitlement
        // Read from its cache at start; in a cold worker process, wait briefly rather than write "free".
        return withTimeoutOrNull(PRO_WAIT_MILLIS) { entitlement.filterNotNull().first() == Entitlement.PRO } ?: false
    }

    override fun locale(): String = pushLocale(AppLocale.current(context), Locale.getDefault())

    override fun notificationsAllowed(): Boolean? = notificationsAllowed(
        enabled = NotificationManagerCompat.from(context).areNotificationsEnabled(),
        needsPermission = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU,
        permissionGranted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED,
        asked = store.notificationsAsked
    )

    override val appVersion: String = BuildConfig.VERSION_NAME
    override val isDebug: Boolean = BuildConfig.DEBUG

    companion object {
        private const val PRO_WAIT_MILLIS = 3_000L

        /** The language alerts are written in: Help's choice, else the phone's, as one of the two the app has. */
        fun pushLocale(language: AppLanguage, system: Locale): String = when (language) {
            AppLanguage.TRADITIONAL_CHINESE -> AppLanguage.TRADITIONAL_CHINESE.id

            AppLanguage.ENGLISH -> AppLanguage.ENGLISH.id

            AppLanguage.SYSTEM -> if (system.language ==
                "zh"
            ) {
                AppLanguage.TRADITIONAL_CHINESE.id
            } else {
                AppLanguage.ENGLISH.id
            }
        }

        /**
         * Allowed when Android shows the app's notifications; denied when it doesn't. On Android 13+
         * a permission never asked for is unknown (null), not "no", as iOS treats "not determined":
         * the sender waits for true, which the answer to the prompt writes at once.
         */
        fun notificationsAllowed(
            enabled: Boolean,
            needsPermission: Boolean,
            permissionGranted: Boolean,
            asked: Boolean
        ): Boolean? = when {
            enabled -> true
            needsPermission && !permissionGranted && !asked -> null
            else -> false
        }
    }
}

/**
 * The favourites list in FOX-55's shared preferences (`favourites` / `savedFavouriteStations`,
 * `"126,85"`), until its repository is wired in through [PushGraph.favourites].
 */
class PreferencesFavouriteStations(context: Context) : FavouriteStations {
    private val prefs = context.getSharedPreferences("favourites", Context.MODE_PRIVATE)

    private fun read(): List<Int> = prefs.getString(KEY, null)
        ?.split(',')?.mapNotNull { it.trim().toIntOrNull() }?.distinct()
        ?: listOf(DEFAULT_FAVOURITE)

    override fun contains(stationId: Int): Boolean = stationId in read()

    override fun add(stationId: Int): Boolean {
        val list = read()
        if (stationId in list) return false
        prefs.edit { putString(KEY, (list + stationId).joinToString(",")) }
        return true
    }

    private companion object {
        const val KEY = "savedFavouriteStations"

        /** A new install starts with one favourite, as on iOS and in FOX-55. */
        const val DEFAULT_FAVOURITE = 126
    }
}

/** Runs [PushSync.sync] in WorkManager: once online, after the debounce, retried with backoff until it lands. */
class WorkManagerSyncScheduler(private val context: Context) : SyncScheduler {
    override fun schedule(delayMillis: Long) {
        val request = OneTimeWorkRequestBuilder<PushSyncWorker>()
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setInitialDelay(delayMillis, TimeUnit.MILLISECONDS)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, BACKOFF_SECONDS, TimeUnit.SECONDS)
            .build()
        // Replace: a newer change (a slider step) restarts the wait, and the run reads the latest
        // saved state anyway. Writes are idempotent, so a replaced run in flight loses nothing.
        WorkManager.getInstance(context).enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.REPLACE, request)
    }

    companion object {
        const val WORK_NAME = "push-sync"
        const val BACKOFF_SECONDS = 30L
    }
}

class PushSyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = when (PushGraph.sync(applicationContext).sync()) {
        PushSync.Outcome.DONE -> Result.success()
        PushSync.Outcome.RETRY -> Result.retry()
    }
}
