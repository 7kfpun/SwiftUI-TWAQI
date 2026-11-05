//
//  OnboardingViewModel.swift
//  TWAQI
//
//  Created by kf on 2/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import CoreLocation
import Foundation
import UIKit
import UserNotifications

@MainActor
final class OnboardingViewModel: ObservableObject {
    enum LocationState: Equatable {
        case notAsked
        case asking
        case on
        case off
    }

    enum NotificationState: Equatable {
        case notAsked
        case asking
        case on
        case off
    }

    enum ClosestState: Equatable {
        case loading
        case loaded(OnboardingClosestStation)
        case failed
    }

    @Published var step: Onboarding.Step = .welcome {
        didSet {
            if step != oldValue {
                logStepViewed()
            }
        }
    }
    @Published private(set) var locationState: LocationState = .notAsked
    @Published private(set) var notificationState: NotificationState = .notAsked
    @Published private(set) var closest: ClosestState = .loading

    /// The station screen's own model for the suggested station, so adding it
    /// goes the way the heart on the station screen goes: a favourite, and
    /// its alerts switched on with it (FOX-31).
    @Published private(set) var stationModel: DetailsViewModel?

    /// Every station with its current reading, for choosing another one.
    @Published private(set) var stations: Pollutants = []

    /// The Watch app's one-shot locator, shared with the phone.
    private let locator = Locator()
    /// Only read for its status: reading never prompts.
    private let statusManager = CLLocationManager()
    private var location: CLLocation?
    /// The location prompt's answer and the pause after a grant. Cancelled
    /// when the flow ends, so nothing moves the step after Skip or Done.
    private var locationTask: Task<Void, Never>?

    init() {
        refreshLocationState()
        refreshNotificationState()
        logStepViewed()
    }

    private func logStepViewed() {
        TrackingManager.logEvent(.onboardingStepViewed, parameters: [
            "step": step.analyticsName,
            "index": step.analyticsIndex,
        ])
    }

    // MARK: - Navigation

    func goForward() {
        if let next = step.next {
            step = next
        }
    }

    func goBack() {
        if let previous = step.previous {
            step = previous
        }
    }

    /// How long a granted permission's success shows before the flow moves
    /// on by itself.
    private static let successPause: UInt64 = 1_200_000_000

    // MARK: - Location (step 2 only)

    func refreshLocationState() {
        switch statusManager.authorizationStatus {
        case .notDetermined:
            locationState = .notAsked
        case .denied, .restricted:
            locationState = .off
        default:
            locationState = .on
        }
    }

    /// The system location prompt. Only the location step calls this.
    func requestLocation() {
        guard locationState != .asking else { return }
        // Only a real prompt's answer is logged, not a status decided earlier.
        let prompts = statusManager.authorizationStatus == .notDetermined
        locationState = .asking
        locationTask = Task {
            location = await locator.current()
            refreshLocationState()
            if prompts, locationState == .on || locationState == .off {
                TrackingManager.logEvent(.onboardingLocation, parameters: [
                    "label": locationState == .on ? "on" : "off",
                ])
            }
            // Back from the station step with location now on: find the
            // station near the reader instead of the 中正 stand-in.
            if location != nil, case .loaded(let shown) = closest, shown.isFallback {
                closest = .loading
                stationModel = nil
            }
            if locationState == .on, prompts {
                // Let the step's success show, unless the reader moved on already.
                try? await Task.sleep(nanoseconds: Self.successPause)
                if !Task.isCancelled, step == .location {
                    goForward()
                }
            } else if locationState == .on || locationState == .off {
                goForward()
            }
        }
    }

    // MARK: - Closest station (step 3)

    /// Finds the nearest station, or the one nearest 中正 without a location.
    /// Never prompts: the locator is used only once location is allowed.
    func loadClosestStation() {
        if case .loaded = closest { return }
        closest = .loading

        Task {
            refreshLocationState()
            if location == nil, locationState == .on {
                location = await locator.current()
            }

            let stations = await Self.currentStations()
            self.stations = stations
            // A station chosen meanwhile stays.
            if case .loaded = closest { return }
            guard let resolved = OnboardingClosestStation.resolve(location: location, in: stations) else {
                closest = .failed
                return
            }
            show(resolved)
        }
    }

    /// The reader picked another station from the list. Kept when they go
    /// back and forth, and over the 中正 stand-in.
    func chooseStation(_ pollutant: Pollutant) {
        if case .loaded(let shown) = closest, shown.pollutant.stationId == pollutant.stationId { return }
        show(OnboardingClosestStation(pollutant: pollutant, origin: .chosen))
        TrackingManager.logEvent(.onboardingChooseStation, parameters: [
            "stationId": pollutant.stationId,
        ])
    }

    private func show(_ station: OnboardingClosestStation) {
        closest = .loaded(station)

        let model = DetailsViewModel(stationId: station.pollutant.stationId, pollutant: station.pollutant)
        // Loads the station's cam, whose SiteId its alerts are stored with.
        model.getData()
        stationModel = model
    }

    func addClosestStationToFavourites() {
        guard let model = stationModel, !model.isFavourited else { return }
        guard model.canAddFavourite else { return }
        model.favouriteStationToggle()
        objectWillChange.send()
        TrackingManager.logEvent(.onboardingAddFavourite, parameters: [
            "stationId": model.stationId,
        ])
    }

    private static func currentStations() async -> Pollutants {
        await withCheckedContinuation { continuation in
            APIManager.getCurrentPollutants(countryCode: WatchStore.countryCode) { result in
                switch result {
                case .success(let pollutants):
                    continuation.resume(returning: pollutants)
                case .failure:
                    // Offline: the map's last good list, if it has one.
                    continuation.resume(returning: PollutantCache.shared.pollutants(countryCode: WatchStore.countryCode) ?? [])
                }
            }
        }
    }

    // MARK: - Notifications (step 4 only)

    /// Quiet hours show on this step once notifications are on.
    var showsQuietHours: Bool {
        Onboarding.showsQuietHours(notificationsOn: notificationState == .on)
    }

    func refreshNotificationState() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let state: NotificationState
            switch settings.authorizationStatus {
            case .notDetermined:
                state = .notAsked
            case .denied:
                state = .off
            default:
                state = .on
            }
            Task { @MainActor in
                if self.notificationState != .asking {
                    self.notificationState = state
                }
            }
        }
    }

    /// The system notification prompt. The app registered with APNs at
    /// launch already (see `AppDelegate`). Only the notifications step calls
    /// this.
    func requestNotifications() {
        guard notificationState != .asking else { return }
        notificationState = .asking

        let answered: (Bool) -> Void = { accepted in
            Task { @MainActor in
                // Tell the sender now whether this device can show alerts.
                DirectusPushMirror.shared.notificationsChanged()
                self.notificationState = accepted ? .on : .off
                TrackingManager.logEvent(.onboardingNotifications, parameters: [
                    "label": accepted ? "on" : "off",
                ])
                // A yes stays here for quiet hours; a no moves on.
                if Onboarding.advancesAfterNotificationAnswer(accepted: accepted), self.step == .notifications {
                    self.goForward()
                }
            }
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { accepted, _ in
            answered(accepted)
        }
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Finish

    /// Finished or skipped. The flow was marked shown when it opened, so it
    /// won't open by itself again either way; Help can run it anytime.
    /// `isLaunchFlow`: this run opened by itself at launch, so finishing it
    /// ends the launch-time hold; a Help run leaves the hold alone.
    func finish(skippedAt skipped: Onboarding.Step? = nil, isLaunchFlow: Bool) {
        locationTask?.cancel()
        Onboarding.flowEnded(isLaunchFlow: isLaunchFlow)
        if let skipped {
            TrackingManager.logEvent(.onboardingSkipped, parameters: [
                "label": "step_\(skipped.analyticsIndex)",
            ])
        } else {
            TrackingManager.logEvent(.onboardingCompleted)
        }
    }
}
