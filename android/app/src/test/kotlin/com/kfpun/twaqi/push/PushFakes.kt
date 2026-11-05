package com.kfpun.twaqi.push

import java.time.Instant

/** A push API that records each call and fails the ones a test asks it to. */
class FakePushApi : PushApi {
    var rowId = 7
    var restored = RestoredDevice(device = null, subscriptions = emptyList())

    /** Thrown by the next call of that kind, then cleared. */
    var failUpsert: Exception? = null
    var failReconcile: Exception? = null
    var failRestore: Exception? = null
    var failArchiveAll: Exception? = null

    val upserts = mutableListOf<PushDevicePayload>()
    val reconciles = mutableListOf<Triple<String, String?, StationAlerts>>()
    var restores = 0
    var archiveAlls = 0

    /** Identities each call was made with. */
    val deviceIds = mutableListOf<String>()

    override suspend fun upsertDevice(payload: PushDevicePayload): Int {
        failUpsert?.let {
            failUpsert = null
            throw it
        }
        upserts += payload
        deviceIds += payload.deviceId
        return rowId
    }

    override suspend fun restore(): RestoredDevice {
        failRestore?.let {
            failRestore = null
            throw it
        }
        restores++
        return restored
    }

    override suspend fun reconcile(stationId: String, siteId: String?, alerts: StationAlerts) {
        failReconcile?.let {
            failReconcile = null
            throw it
        }
        reconciles += Triple(stationId, siteId, alerts)
    }

    override suspend fun archiveAll() {
        failArchiveAll?.let {
            failArchiveAll = null
            throw it
        }
        archiveAlls++
    }
}

class FakeIdentity : PushIdentity {
    private var id: String? = null
    private var secret: String? = null
    var resets = 0
    private var made = 0

    override fun id(): String = id ?: "6f1c2e7a-0000-4000-8000-00000000000${++made}".also { id = it }

    override fun secret(): String = secret ?: PushIdentity.newSecret().also { secret = it }

    override fun reset() {
        resets++
        id = null
        secret = null
    }
}

class FakeProfile(var pro: Boolean = false, var language: String = "en", var allowed: Boolean? = true) :
    DeviceProfileSource {
    override suspend fun isPro() = pro
    override fun locale() = language
    override fun notificationsAllowed() = allowed
    override val appVersion = "2.0.0"
    override val isDebug = false
}

class RecordingScheduler : SyncScheduler {
    val delays = mutableListOf<Long>()

    override fun schedule(delayMillis: Long) {
        delays += delayMillis
    }
}

/** A [PushSync] on fakes, with an FCM token and a push API URL, like a phone that registered. */
class SyncHarness(
    val store: InMemoryPushStore = InMemoryPushStore().apply { fcmToken = "fcm-1" },
    val api: FakePushApi = FakePushApi(),
    val identity: FakeIdentity = FakeIdentity(),
    val profile: FakeProfile = FakeProfile(),
    val scheduler: RecordingScheduler = RecordingScheduler(),
    baseUrl: String? = "https://push.example.com",
    var now: Instant = Instant.parse("2026-11-06T00:00:00Z")
) {
    val configs = mutableListOf<PushConfig>()
    val sync = PushSync(
        store = store,
        identity = identity,
        baseUrl = baseUrl,
        apiFactory = { config ->
            configs += config
            api
        },
        profile = profile,
        scheduler = scheduler,
        clock = { now }
    )
}

class FakeFavourites(initial: List<Int> = emptyList()) : FavouriteStations {
    val list = initial.toMutableList()

    override fun contains(stationId: Int) = stationId in list

    override fun add(stationId: Int): Boolean {
        if (stationId in list) return false
        list += stationId
        return true
    }
}

class RecordingLogger : EventLogger {
    val events = mutableListOf<Pair<String, Map<String, String>>>()

    override fun log(name: String, parameters: Map<String, String>) {
        events += name to parameters
    }
}
