package com.kfpun.twaqi.ui.station.cam

import com.kfpun.twaqi.data.cams.CamFrameSource
import com.kfpun.twaqi.data.cams.CamHistorySource
import com.kfpun.twaqi.data.cams.CamHourResult
import com.kfpun.twaqi.data.cams.StationCam
import com.kfpun.twaqi.data.cams.StationCamHour
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * The live frame on screen.
 *
 * @property image the frame shown, saved or fresh.
 * @property imageTime capture time of [image]: not necessarily the manifest's, while an older
 *   saved frame stands in.
 * @property refreshFailed the latest frame couldn't be loaded; [image], if any, is an older one.
 */
data class CamFrameState<T>(
    val image: T? = null,
    val imageTime: String? = null,
    val isRefreshing: Boolean = false,
    val refreshFailed: Boolean = false
)

/**
 * Loads one cam's frame: the saved one first, then the latest (iOS `StationCamFrameLoader`).
 * Called from [scope] on the main thread; [source] does its own IO.
 */
class StationCamFrameLoader<T>(private val source: CamFrameSource<T>, private val scope: CoroutineScope) {
    private val mutableState = MutableStateFlow(CamFrameState<T>())
    val state: StateFlow<CamFrameState<T>> = mutableState.asStateFlow()

    /** The cam last asked for; an answer for any other is dropped. */
    private var currentCam: StationCam? = null

    /**
     * Shows [cam]'s saved frame, then fetches its latest. Called on every appearance: the same cam
     * loads again only if its last fetch failed.
     */
    fun load(cam: StationCam) {
        val current = mutableState.value
        if (cam == currentCam && (current.isRefreshing || !current.refreshFailed)) return
        val sameSite = cam.siteId == currentCam?.siteId
        currentCam = cam
        mutableState.value = current.copy(
            image = if (sameSite) current.image else null,
            imageTime = if (sameSite) current.imageTime else null,
            isRefreshing = true,
            refreshFailed = false
        )

        scope.launch {
            val saved = source.savedFrame(cam.siteId)
            if (currentCam != cam) return@launch
            if (mutableState.value.image == null && saved != null) {
                mutableState.value = mutableState.value.copy(image = saved.image, imageTime = saved.time)
            }
            // The saved frame is the manifest's latest: nothing to fetch.
            if (saved != null && saved.time != null && saved.time == cam.time) {
                mutableState.value =
                    mutableState.value.copy(image = saved.image, imageTime = saved.time, isRefreshing = false)
                return@launch
            }

            val fresh = source.fetch(cam)
            if (currentCam != cam) return@launch
            mutableState.value = if (fresh != null) {
                mutableState.value.copy(image = fresh.image, imageTime = fresh.time, isRefreshing = false)
            } else {
                mutableState.value.copy(isRefreshing = false, refreshFailed = true)
            }
        }
    }
}

/** How far one hour of the scrubber has got. */
enum class CamSlotState { LOADING, LOADED, MISSING, FAILED }

/**
 * The scrubber's side of the cam.
 *
 * @property slots the 24 hours on offer, oldest first.
 * @property selected the hour picked on the scrubber; null is live.
 * @property image what the frame shows for [selected]: its full-res frame once settled, its
 *   thumbnail while scrubbing, or the last frame shown, standing in while it loads.
 * @property isStandIn [image] is an earlier frame standing in while [selected] loads.
 */
data class CamHistoryState<T>(
    val slots: List<StationCamHour> = emptyList(),
    val states: Map<StationCamHour, CamSlotState> = emptyMap(),
    val selected: StationCamHour? = null,
    val image: T? = null,
    val isStandIn: Boolean = false
) {
    val selectedState: CamSlotState? get() = selected?.let { states[it] }
}

/**
 * The past 24 clock hours, one frame each (iOS `StationCamHistoryLoader`).
 *
 * Lazy by design. While the finger moves, only the hour under it is shown, from memory or a
 * downsampled decode of its saved file, never the network. When the scrubber comes to rest, that
 * hour and two either side load (disk, then network), the rest are forgotten, and the resting
 * hour's full-res frame replaces its thumbnail. Nothing fetches the whole day.
 *
 * While an hour loads, whatever was on screen stays up as a stand-in, so the frame never drops
 * back to a spinner. An hour with no frame (a 404) is [CamSlotState.MISSING], never
 * [CamSlotState.FAILED], and is asked for again after [MISSING_RETRY].
 */
class StationCamHistoryLoader<T>(
    private val source: CamHistorySource<T>,
    private val scope: CoroutineScope,
    private val now: () -> Instant = Instant::now
) {
    private val mutableState = MutableStateFlow(CamHistoryState<T>())
    val state: StateFlow<CamHistoryState<T>> = mutableState.asStateFlow()

    private var slots: List<StationCamHour> = emptyList()
    private var states: Map<StationCamHour, CamSlotState> = emptyMap()
    private var selected: StationCamHour? = null
    private var image: T? = null
    private var isStandIn = false

    /** Thumbnails of [window], plus the hour under the finger. */
    private var thumbnails: Map<StationCamHour, T> = emptyMap()
    private var full: Pair<StationCamHour, T>? = null
    private var settled: StationCamHour? = null

    /** The settled hour and its neighbours: the only hours fetched, and the only thumbnails kept. */
    private var window: Set<StationCamHour> = emptySet()
    private var missingAt: Map<StationCamHour, Instant> = emptyMap()

    /**
     * The 24 hours up to [anchor] (the live frame's capture time). A new anchor slides the window;
     * hours still in it keep what they loaded.
     */
    fun configure(siteId: String, anchor: Instant) {
        val next = StationCamHour.slots(siteId, anchor)
        if (next == slots) return

        if (next.firstOrNull()?.siteId != slots.firstOrNull()?.siteId) {
            states = emptyMap()
            thumbnails = emptyMap()
            missingAt = emptyMap()
            full = null
            settled = null
            window = emptySet()
            selected = null
            image = null
            isStandIn = false
        } else {
            val kept = next.toSet()
            states = states.filterKeys { it in kept }
            thumbnails = thumbnails.filterKeys { it in kept }
            missingAt = missingAt.filterKeys { it in kept }
            if (full?.first !in kept) full = null
            if (selected != null && selected !in kept) showLive(publish = false)
        }
        slots = next
        publish()
    }

    /** Back to the live frame. */
    fun showLive() = showLive(publish = true)

    private fun showLive(publish: Boolean) {
        selected = null
        settled = null
        if (publish) publish()
    }

    /**
     * Scrubbing over [index]: shows it if it's in memory or on disk. No network. [standIn] is
     * shown meanwhile if nothing is up yet.
     */
    fun preview(index: Int, standIn: T?) {
        val hour = slots.getOrNull(index) ?: return
        if (selected == null && (image == null || standIn != null)) image = standIn
        selected = hour
        if (settled != hour) settled = null
        show(hour)
        publish()

        if (thumbnails[hour] != null || states[hour] == CamSlotState.MISSING) return
        scope.launch {
            val thumbnail = source.savedThumbnail(hour) ?: return@launch
            if (selected != hour || hour !in slots) return@launch
            // One scrubbing thumbnail at a time, on top of the settled window.
            thumbnails = thumbnails.filterKeys { it in window } + (hour to thumbnail)
            states = states + (hour to CamSlotState.LOADED)
            show(hour)
            publish()
        }
    }

    /** The scrubber came to rest on [index]: it and its neighbours load, and its full-res frame replaces the thumbnail. */
    fun settle(index: Int) {
        val hour = slots.getOrNull(index) ?: return
        selected = hour
        settled = hour

        val nearby = StationCamHour.window(index).map { slots[it] }
        window = nearby.toSet()
        thumbnails = thumbnails.filterKeys { it in window }
        if (full != null && full?.first != hour) full = null

        show(hour)
        publish()
        nearby.forEach(::load)
    }

    private fun load(hour: StationCamHour) {
        when (states[hour]) {
            CamSlotState.LOADING -> return

            CamSlotState.MISSING -> {
                val at = missingAt[hour]
                if (at != null && Duration.between(at, now()) < MISSING_RETRY) return
            }

            else -> Unit
        }
        if (thumbnails[hour] != null) {
            loadFull(hour)
            return
        }

        states = states + (hour to CamSlotState.LOADING)
        if (selected == hour) show(hour)
        publish()
        scope.launch {
            val result = source.load(hour)
            if (hour !in slots) return@launch
            when (result) {
                is CamHourResult.Thumbnail -> {
                    states = states + (hour to CamSlotState.LOADED)
                    missingAt = missingAt - hour
                    // Kept only if still near where the scrubber rests.
                    if (hour in window || selected == hour) thumbnails = thumbnails + (hour to result.image)
                    loadFull(hour)
                }

                CamHourResult.Missing -> {
                    states = states + (hour to CamSlotState.MISSING)
                    missingAt = missingAt + (hour to now())
                }

                CamHourResult.Failed -> states = states + (hour to CamSlotState.FAILED)
            }
            if (selected == hour) show(hour)
            publish()
        }
    }

    /** Full-res decode, for the settled hour only. */
    private fun loadFull(hour: StationCamHour) {
        if (settled != hour || full?.first == hour) return
        scope.launch {
            val decoded = source.savedFullImage(hour) ?: return@launch
            if (settled != hour) return@launch
            full = hour to decoded
            show(hour)
            publish()
        }
    }

    private fun show(hour: StationCamHour) {
        if (selected != hour) return
        val full = full
        val thumbnail = thumbnails[hour]
        if (full != null && full.first == hour) {
            image = full.second
            isStandIn = false
        } else if (thumbnail != null) {
            image = thumbnail
            isStandIn = false
        } else {
            // Loading, not asked for yet, or nothing to show (the view puts a placeholder over a
            // missing hour): keep the last frame up for later.
            isStandIn = image != null
        }
    }

    private fun publish() {
        mutableState.value = CamHistoryState(slots, states, selected, image, isStandIn)
    }

    companion object {
        /** A 404'd hour is asked for again after this long: its frame may not have been filed yet. */
        val MISSING_RETRY: Duration = Duration.ofMinutes(5)
    }
}
