//
//  OnboardingView.swift
//  TWAQI
//
//  Created by kf on 2/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// The welcome flow (FOX-34), one step at a time.
///
/// Skipping: every step can be continued without doing what it asks ("Not
/// now"), and "Skip" at the top ends the whole flow. It opens by itself once
/// (FOX-49), counted when it opens rather than when it ends; Help runs it
/// anytime.
struct OnboardingView: View {
    /// Quiet hours, written as Help writes them. Help passes its own model;
    /// at launch the flow has one of its own.
    private let sharedDoNotDisturb: HelpViewModel?
    private let onFinish: () -> Void

    @StateObject private var settings = SettingsStore()
    @StateObject private var viewModel = OnboardingViewModel()
    @StateObject private var ownDoNotDisturb = HelpViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingPro = false

    private let accent = Color(0x5AC8FA)

    init(doNotDisturb: HelpViewModel? = nil, onFinish: @escaping () -> Void) {
        self.sharedDoNotDisturb = doNotDisturb
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(spacing: 20) {
                    stepContent
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            // Each step starts at its top.
            .id(viewModel.step)

            actions
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .frame(maxWidth: 560)
        }
        .background(Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all))
        .animation(.easeInOut(duration: 0.2), value: viewModel.step)
        .sheet(isPresented: $showingPro) {
            ProView()
        }
        // Back from Settings with location or notifications changed.
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                viewModel.refreshLocationState()
                viewModel.refreshNotificationState()
            }
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            if viewModel.step.previous != nil {
                Button(action: viewModel.goBack) {
                    Image(systemName: "chevron.backward")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel(Text("Onboarding.back"))
            }

            Spacer()

            if !viewModel.step.isLast {
                Button("Onboarding.skip") {
                    finish(skippedAt: viewModel.step)
                }
            }
        }
        // Keeps the dots centred whichever buttons show.
        .overlay(pageDots)
        .frame(height: 44)
        .padding(.horizontal, 16)
        .accentColor(accent)
        .foregroundColor(accent)
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(Onboarding.Step.allCases) { step in
                Circle()
                    .fill(step == viewModel.step ? accent : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Onboarding.step \(viewModel.step.rawValue + 1) \(Onboarding.Step.allCases.count)"))
    }

    private func header(icon: String, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundColor(accent)
                .padding(.top, 24)
                .accessibilityHidden(true)

            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(body)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func note(_ text: LocalizedStringKey, icon: String = "info.circle") -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .welcome:
            header(icon: "aqi.medium", title: "Onboarding.welcome_title", body: "Onboarding.welcome_body")
        case .location:
            locationStep
        case .closestStation:
            closestStationStep
        case .notifications:
            notificationsStep
        case .doNotDisturb:
            doNotDisturbStep
        case .dataSource:
            header(icon: "building.columns", title: "Onboarding.data_title", body: "Onboarding.data_body")
            note("Onboarding.data_independent")
        case .premium:
            premiumStep
        }
    }

    @ViewBuilder
    private var locationStep: some View {
        header(icon: "location.circle", title: "Onboarding.location_title", body: "Onboarding.location_body")

        switch viewModel.locationState {
        case .on:
            note("Onboarding.location_on", icon: "checkmark.circle")
        case .off:
            note("Onboarding.location_off")
        case .notAsked, .asking:
            EmptyView()
        }
    }

    @ViewBuilder
    private var closestStationStep: some View {
        header(icon: "heart.circle", title: "Onboarding.closest_title", body: "Onboarding.closest_body")

        Group {
            switch viewModel.closest {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 88)
            case .failed:
                note("Onboarding.closest_failed", icon: "wifi.exclamationmark")
            case .loaded(let closest):
                OnboardingStationCard(pollutant: closest.pollutant)

                if closest.isFallback {
                    note("Onboarding.closest_fallback", icon: "location.slash")
                }

                if let model = viewModel.stationModel {
                    OnboardingFavouriteStatus(model: model)
                }
            }
        }
        .onAppear(perform: viewModel.loadClosestStation)
    }

    @ViewBuilder
    private var notificationsStep: some View {
        header(icon: "bell.badge", title: "Onboarding.notifications_title", body: "Onboarding.notifications_body")

        switch viewModel.notificationState {
        case .on:
            note("Onboarding.notifications_on", icon: "checkmark.circle")
        case .off:
            note("Onboarding.notifications_off")
        case .notAsked, .asking:
            EmptyView()
        }
    }

    @ViewBuilder
    private var doNotDisturbStep: some View {
        header(icon: "moon", title: "Onboarding.dnd_title", body: "Onboarding.dnd_body")

        OnboardingDoNotDisturb(viewModel: sharedDoNotDisturb ?? ownDoNotDisturb)

        note("Onboarding.dnd_footer")
    }

    @ViewBuilder
    private var premiumStep: some View {
        header(icon: "sparkles", title: "Pro.title", body: "Onboarding.premium_body")

        VStack(alignment: .leading, spacing: 8) {
            ForEach(ProFeature.allCases) { feature in
                ProFeatureRow(feature: feature)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if settings.isPro {
            note("Onboarding.premium_active", icon: "checkmark.seal")
        }
    }

    // MARK: - Buttons

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 8) {
            primaryButton
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(accent)

            secondaryButton
                .buttonStyle(.borderless)
                .tint(accent)
                .frame(minHeight: 36)
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch viewModel.step {
        case .welcome:
            wideButton("Onboarding.get_started", action: viewModel.goForward)
        case .location:
            switch viewModel.locationState {
            case .notAsked:
                wideButton("Onboarding.enable_location", action: viewModel.requestLocation)
            case .asking:
                wideButton("Onboarding.enable_location") {}
                    .disabled(true)
            case .on, .off:
                wideButton("Onboarding.continue", action: viewModel.goForward)
            }
        case .closestStation:
            if canAddClosestStation {
                wideButton("Onboarding.add_to_favourites", action: viewModel.addClosestStationToFavourites)
            } else {
                wideButton("Onboarding.continue", action: viewModel.goForward)
            }
        case .notifications:
            switch viewModel.notificationState {
            case .notAsked:
                wideButton("Onboarding.allow_notifications", action: viewModel.requestNotifications)
            case .asking:
                wideButton("Onboarding.allow_notifications") {}
                    .disabled(true)
            case .on, .off:
                wideButton("Onboarding.continue", action: viewModel.goForward)
            }
        case .doNotDisturb, .dataSource:
            wideButton("Onboarding.continue", action: viewModel.goForward)
        case .premium:
            wideButton("Onboarding.done") { finish() }
        }
    }

    @ViewBuilder
    private var secondaryButton: some View {
        switch viewModel.step {
        case .location where viewModel.locationState == .notAsked,
             .notifications where viewModel.notificationState == .notAsked:
            Button("Onboarding.not_now", action: viewModel.goForward)
        case .location where viewModel.locationState == .off,
             .notifications where viewModel.notificationState == .off:
            Button("Onboarding.open_settings", action: viewModel.openSettings)
        case .closestStation where canAddClosestStation:
            Button("Onboarding.not_now", action: viewModel.goForward)
        case .premium where !settings.isPro:
            Button("Onboarding.see_pro_plans") {
                showingPro = true
                TrackingManager.logEvent(eventName: "onboarding_open_pro")
            }
        default:
            // Keeps the primary button where it was from step to step.
            Text(verbatim: " ")
                .accessibilityHidden(true)
        }
    }

    private var canAddClosestStation: Bool {
        guard let model = viewModel.stationModel else { return false }
        return !model.isFavourited
    }

    private func wideButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
    }

    private func finish(skippedAt step: Onboarding.Step? = nil) {
        viewModel.finish(skippedAt: step)
        onFinish()
    }
}

/// The suggested station's current AQI.
private struct OnboardingStationCard: View {
    var pollutant: Pollutant

    var body: some View {
        let value = pollutant.getValue(airIndexType: .aqi)
        let status = AirStatuses.checkAirStatus(airIndexType: .aqi, value: value)

        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: pollutant.displayName)
                    .font(.title3.bold())
                if let locality = pollutant.displayLocality {
                    Text(verbatim: locality)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Text(status.toString())
                    .font(.subheadline)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(verbatim: "AQI")
                    .font(.caption.bold())
                Text(verbatim: value != 0 ? value.format(f: AirIndexTypes.aqi.getFormat()) : "-")
                    .font(.title.bold())
            }
            .foregroundColor(Color(status.getForegroundColor()))
            .frame(width: 72, height: 72)
            .background(Color(status.getColor()))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// What adding the suggested station did, as the station screen reports it.
private struct OnboardingFavouriteStatus: View {
    @ObservedObject var model: DetailsViewModel

    var body: some View {
        if model.isFavourited {
            VStack(alignment: .leading, spacing: 8) {
                Label("Onboarding.in_favourites", systemImage: "heart.fill")
                if model.hasAlerts {
                    Label("Favourites.alerts_on", systemImage: "bell.fill")
                } else if model.favouriteAlertsHint == .capReached {
                    Label("Favourites.alerts_cap_reached_message", systemImage: "bell.slash")
                        .foregroundColor(.secondary)
                } else if model.favouriteAlertsHint == .notificationsDenied {
                    Label("Onboarding.alerts_need_notifications", systemImage: "bell.slash")
                        .foregroundColor(.secondary)
                }
            }
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Help's quiet-hours controls, written through Help's own model.
private struct OnboardingDoNotDisturb: View {
    @ObservedObject var viewModel: HelpViewModel

    var body: some View {
        VStack(spacing: 12) {
            Toggle(isOn: $viewModel.isDndEnabled.animation()) {
                Text("Help.turn_on_do_not_disturb")
            }

            if viewModel.isDndEnabled {
                DatePicker(
                    selection: $viewModel.dndStartTime,
                    displayedComponents: .hourAndMinute,
                    label: { Text("Help.start_time") }
                )

                DatePicker(
                    selection: $viewModel.dndEndTime,
                    displayedComponents: .hourAndMinute,
                    label: { Text("Help.end_time") }
                )
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        ForEach(["zh-Hant", "en"], id: \.self) { localIdentifier in
            OnboardingView(onFinish: {})
                .environment(\.locale, .init(identifier: localIdentifier))
                .previewDisplayName(localIdentifier)
        }
    }
}
