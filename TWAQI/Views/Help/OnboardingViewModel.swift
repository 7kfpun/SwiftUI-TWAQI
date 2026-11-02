//
//  OnboardingViewModel.swift
//  TWAQI
//
//  Created by kf on 2/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import CoreLocation
import Foundation
import OneSignal
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

    @Published var step: Onboarding.Step = .welcome
    @Published private(set) var locationState: LocationState = .notAsked
    @Published private(set) var notificationState: NotificationState = .notAsked
    @Published private(set) var closest: ClosestState = .loading

    /// The station screen's own model for the suggested station, so adding it
    /// goes the way the heart on the station screen goes: a favourite, and
    /// its alerts switched on with it (FOX-31), OneSignal first, Directus after.
    @Published private(set) var stationModel: DetailsViewModel?

    /// The Watch app's one-shot locator, shared with the phone.
    private let locator = Locator()
    /// Only read for its status: reading never prompts.
    private let statusManager = CLLocationManager()
    private var location: CLLocation?

    init() {
        refreshLocationState()
        refreshNotificationState()
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
        locationState = .asking
        Task {
            location = await locator.current()
            refreshLocationState()
            // Back from the station step with location now on: find the
            // station near the reader instead of the 中正 stand-in.
            if location != nil, case .loaded(let shown) = closest, shown.isFallback {
                closest = .loading
                stationModel = nil
            }
            if locationState == .on || locationState == .off {
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
            guard let resolved = OnboardingClosestStation.resolve(location: location, in: stations) else {
                closest = .failed
                return
            }
            closest = .loaded(resolved)

            let model = DetailsViewModel(stationId: resolved.pollutant.stationId)
            // Loads the station record, which names the OneSignal tag the
            // alerts go under.
            model.getData()
            stationModel = model
        }
    }

    func addClosestStationToFavourites() {
        guard let model = stationModel, !model.isFavourited else { return }
        model.favouriteStationToggle()
        objectWillChange.send()
        TrackingManager.logEvent(eventName: "onboarding_add_favourite", parameters: [
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

    /// The system notification prompt, through OneSignal, which owns push
    /// permission and APNs registration. Only the notifications step calls this.
    func requestNotifications() {
        guard notificationState != .asking else { return }
        notificationState = .asking

        let answered: (Bool) -> Void = { accepted in
            Task { @MainActor in
                self.notificationState = accepted ? .on : .off
                TrackingManager.logEvent(eventName: "onboarding_notifications", parameters: [
                    "label": accepted ? "on" : "off",
                ])
                self.goForward()
            }
        }

        if getEnv("OneSignalAppId") != nil {
            OneSignal.promptForPushNotifications(userResponse: answered)
        } else {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { accepted, _ in
                answered(accepted)
            }
        }
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Finish

    /// Finished or skipped. Either way the flow won't open by itself again;
    /// Help can run it anytime.
    func finish(skippedAt skipped: Onboarding.Step? = nil) {
        OnboardingStore().markCompleted()
        NotificationCenter.default.post(name: Onboarding.didFinish, object: nil)
        TrackingManager.logEvent(eventName: "onboarding_finished", parameters: [
            "label": skipped.map { "skipped_\($0.rawValue + 1)" } ?? "completed",
        ])
    }
}
