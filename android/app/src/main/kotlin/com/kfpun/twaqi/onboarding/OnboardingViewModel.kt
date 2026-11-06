package com.kfpun.twaqi.onboarding

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.kfpun.twaqi.TwaqiApplication
import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.ui.main.GeoPoint
import com.kfpun.twaqi.ui.main.LocationAccess
import kotlin.coroutines.resume
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull

/** A runtime permission as the flow shows it (iOS `LocationState`, `NotificationState`). */
enum class PermissionState {
    NOT_ASKED,
    ASKING,
    ON,
    OFF;

    companion object {
        /**
         * Granted is on; refused once asked is off (iOS `.denied`); never asked is not asked yet,
         * which Android can't tell from a refusal by itself, so the app keeps an "asked" flag.
         */
        fun of(granted: Boolean, asked: Boolean): PermissionState = when {
            granted -> ON
            asked -> OFF
            else -> NOT_ASKED
        }
    }
}

/** The closest station step's suggestion (iOS `ClosestState`). */
sealed interface ClosestState {
    data object Loading : ClosestState

    data class Loaded(val station: OnboardingClosestStation) : ClosestState

    data object Failed : ClosestState
}

data class OnboardingUiState(
    val step: OnboardingStep = OnboardingStep.WELCOME,
    val location: PermissionState = PermissionState.NOT_ASKED,
    val notifications: PermissionState = PermissionState.NOT_ASKED,
    val closest: ClosestState = ClosestState.Loading,
    /** Every station with its current reading, for choosing another one. */
    val stations: List<Pollutant> = emptyList()
) {
    /** Quiet hours show on the notifications step once notifications are on. */
    val showsQuietHours: Boolean get() = Onboarding.showsQuietHours(notifications == PermissionState.ON)

    val shownStationId: Int? get() = (closest as? ClosestState.Loaded)?.station?.pollutant?.stationId
}

/**
 * The welcome flow's state (iOS `OnboardingViewModel`). The screen asks for each runtime permission
 * at its step and reports the answer here; this decides where the flow goes next and logs the
 * same events as iOS (`docs/analytics.md` › Onboarding).
 *
 * @param stations every station's current reading, or the last good list offline.
 * @param locate a fix, once location is allowed; never prompts.
 */
class OnboardingViewModel(
    initialLocation: PermissionState,
    initialNotifications: PermissionState,
    private val stations: suspend () -> List<Pollutant>,
    private val locate: suspend () -> GeoPoint?,
    private val logEvent: (String, Map<String, Any>) -> Unit
) : ViewModel() {
    private val state = MutableStateFlow(
        OnboardingUiState(location = initialLocation, notifications = initialNotifications)
    )
    val uiState: StateFlow<OnboardingUiState> = state.asStateFlow()

    private var location: GeoPoint? = null

    /** The location answer and the pause after a grant; cancelled when the flow ends, so nothing moves the step after Skip or Done. */
    private var locationJob: Job? = null
    private var finished = false

    init {
        logStepViewed()
    }

    private fun setStep(step: OnboardingStep) {
        if (finished || step == state.value.step) return
        state.update { it.copy(step = step) }
        logStepViewed()
    }

    private fun logStepViewed() {
        val step = state.value.step
        logEvent(Analytics.ONBOARDING_STEP_VIEWED, mapOf("step" to step.analyticsName, "index" to step.analyticsIndex))
    }

    // Navigation

    fun goForward() {
        state.value.step.next?.let(::setStep)
    }

    fun goBack() {
        state.value.step.previous?.let(::setStep)
    }

    // Permissions, re-read when the app comes back (from Settings, say)

    /** The permissions as Android has them now. A prompt being answered keeps its "asking". */
    fun permissionsChanged(location: PermissionState, notifications: PermissionState) {
        state.update {
            it.copy(
                location = if (it.location == PermissionState.ASKING) it.location else location,
                notifications = if (it.notifications == PermissionState.ASKING) it.notifications else notifications
            )
        }
    }

    // Location (the location step only)

    /** The screen is about to show the system location prompt. */
    fun locationAsked() {
        state.update { it.copy(location = PermissionState.ASKING) }
    }

    /**
     * The location prompt was answered. [prompted]: it wasn't allowed before, so the reader
     * answered a prompt (only that answer is logged, as on iOS).
     */
    fun locationAnswered(granted: Boolean, prompted: Boolean) {
        val answer = if (granted) PermissionState.ON else PermissionState.OFF
        state.update { it.copy(location = answer) }
        if (prompted) {
            logEvent(Analytics.ONBOARDING_LOCATION, mapOf("label" to if (granted) "on" else "off"))
        }
        // The fix comes separately: the step doesn't wait on it.
        if (granted) {
            viewModelScope.launch {
                location = locateOrNull() ?: return@launch
                // Back from the station step with location now on: find the station near the
                // reader instead of the 中正 stand-in. Resolved here, not left to the step: a fix
                // slower than the success pause lands after the step has already asked
                // (loadClosestStation returns while the stand-in is showing). A station the
                // reader chose is not a stand-in, so it stays.
                val shown = (state.value.closest as? ClosestState.Loaded)?.station
                if (shown?.isFallback == true) resolveClosestStation()
            }
        }
        locationJob?.cancel()
        locationJob = viewModelScope.launch {
            if (granted && prompted) {
                // Let the step's success show, unless the reader moved on already.
                delay(SUCCESS_PAUSE_MILLIS)
                if (state.value.step == OnboardingStep.LOCATION) goForward()
            } else if (state.value.step == OnboardingStep.LOCATION) {
                goForward()
            }
        }
    }

    /** A fix, or null when none comes within [LOCATE_TIMEOUT_MILLIS] (indoors, an emulator). */
    private suspend fun locateOrNull(): GeoPoint? = withTimeoutOrNull(LOCATE_TIMEOUT_MILLIS) { locate() }

    // Closest station (step 3)

    /** Finds the nearest station, or the one nearest 中正 without a location. Never prompts. */
    fun loadClosestStation() {
        if (state.value.closest is ClosestState.Loaded) return
        resolveClosestStation()
    }

    /** Shows a spinner, then the station nearest the fix (or 中正 without one). A station chosen meanwhile stays. */
    private fun resolveClosestStation() {
        state.update { it.copy(closest = ClosestState.Loading) }
        viewModelScope.launch {
            if (location == null && state.value.location == PermissionState.ON) location = locateOrNull()
            val all = stations()
            state.update { it.copy(stations = all) }
            // A station chosen meanwhile stays.
            if (state.value.closest is ClosestState.Loaded) return@launch
            val resolved = OnboardingClosestStation.resolve(location, all)
            state.update { it.copy(closest = resolved?.let(ClosestState::Loaded) ?: ClosestState.Failed) }
        }
    }

    /** The reader picked another station from the list. Kept when they go back and forth, and over the 中正 stand-in. */
    fun chooseStation(pollutant: Pollutant) {
        if (state.value.shownStationId == pollutant.stationId) return
        state.update {
            it.copy(
                closest = ClosestState.Loaded(
                    OnboardingClosestStation(pollutant, OnboardingClosestStation.Origin.CHOSEN)
                )
            )
        }
        logEvent(Analytics.ONBOARDING_CHOOSE_STATION, mapOf("stationId" to pollutant.stationId))
    }

    /** The suggested station went into Favourites (its alerts with it, FOX-31). */
    fun favouriteAdded(stationId: Int) {
        logEvent(Analytics.ONBOARDING_ADD_FAVOURITE, mapOf("stationId" to stationId))
    }

    // Notifications (step 4 only)

    /** The screen is about to show the system notification prompt. */
    fun notificationsAsked() {
        state.update { it.copy(notifications = PermissionState.ASKING) }
    }

    fun notificationsAnswered(accepted: Boolean) {
        state.update { it.copy(notifications = if (accepted) PermissionState.ON else PermissionState.OFF) }
        logEvent(Analytics.ONBOARDING_NOTIFICATIONS, mapOf("label" to if (accepted) "on" else "off"))
        // A yes stays here for quiet hours; a no moves on.
        if (Onboarding.advancesAfterNotificationAnswer(accepted) && state.value.step == OnboardingStep.NOTIFICATIONS) {
            goForward()
        }
    }

    // More and Pro (step 5)

    fun proOpened() {
        logEvent(Analytics.ONBOARDING_OPEN_PRO, emptyMap())
    }

    // Finish

    /**
     * Finished ([skippedAt] null) or skipped. The flow was marked shown when it opened, so it won't
     * open by itself again either way; Help can run it anytime. Only the run that opened by itself
     * at launch ends the launch-time hold.
     */
    fun finish(skippedAt: OnboardingStep? = null, isLaunchFlow: Boolean) {
        if (finished) return
        finished = true
        locationJob?.cancel()
        Onboarding.flowEnded(isLaunchFlow)
        if (skippedAt != null) {
            logEvent(Analytics.ONBOARDING_SKIPPED, mapOf("label" to "step_${skippedAt.analyticsIndex}"))
        } else {
            logEvent(Analytics.ONBOARDING_COMPLETED, emptyMap())
        }
    }

    companion object {
        /** How long a granted permission's success shows before the flow moves on by itself (iOS 1.2 s). */
        const val SUCCESS_PAUSE_MILLIS = 1_200L

        /** How long the closest station waits for a fix before it measures from the last known one. */
        const val LOCATE_TIMEOUT_MILLIS = 5_000L

        fun factory(
            app: TwaqiApplication,
            initialLocation: PermissionState,
            initialNotifications: PermissionState
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                val repository = app.container.airQuality
                OnboardingViewModel(
                    initialLocation = initialLocation,
                    initialNotifications = initialNotifications,
                    // Offline: the map's last good list, if it has one.
                    stations = { repository.currentPollutants().valueOrNull.orEmpty() },
                    // A fresh fix; past the timeout, the newest one any provider already has.
                    locate = {
                        withTimeoutOrNull(LOCATE_TIMEOUT_MILLIS - 500) {
                            suspendCancellableCoroutine { continuation ->
                                LocationAccess.current(app) { if (continuation.isActive) continuation.resume(it) }
                            }
                        } ?: LocationAccess.lastKnown(app)
                    },
                    logEvent = { name, parameters -> Analytics.logEvent(app, name, parameters) }
                )
            }
        }
    }
}
