//
//  OnboardingView.swift
//  TWAQI
//
//  Created by kf on 2/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import StoreKit
import SwiftUI

/// The welcome flow (FOX-34), one step at a time, five at most (FOX-84).
///
/// Skipping: every step can be continued without doing what it asks ("Not
/// now"), and "Skip" at the top ends the whole flow. It opens by itself once
/// (FOX-49), counted when it opens rather than when it ends; Help runs it
/// anytime.
struct OnboardingView: View {
    /// Quiet hours, written as Help writes them. Help passes its own model;
    /// at launch the flow has one of its own.
    private let sharedDoNotDisturb: HelpViewModel?
    /// Opened by itself at launch, rather than from Help. Only that run ends
    /// the launch-time hold on the location and review prompts.
    private let isLaunchFlow: Bool
    private let onFinish: () -> Void

    @StateObject private var settings = SettingsStore()
    @StateObject private var viewModel = OnboardingViewModel()
    @StateObject private var ownDoNotDisturb = HelpViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingPro = false
    @State private var showingStationPicker = false
    @State private var guide: OnboardingGuide?

    private let accent = Color(0x5AC8FA)

    init(doNotDisturb: HelpViewModel? = nil, isLaunchFlow: Bool = false, onFinish: @escaping () -> Void) {
        self.sharedDoNotDisturb = doNotDisturb
        self.isLaunchFlow = isLaunchFlow
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
                // A readable width on iPad and in wide windows.
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
            ProView(source: .onboarding)
        }
        .sheet(isPresented: $showingStationPicker) {
            OnboardingStationPicker(stations: viewModel.stations, selectedId: shownStationId) { station in
                viewModel.chooseStation(station)
            }
        }
        .sheet(item: $guide) { guide in
            OnboardingGuideSheet(guide: guide)
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
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
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
        .frame(minHeight: 44)
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
        .accessibilityLabel(Text("Onboarding.step \(viewModel.step.analyticsIndex) \(Onboarding.Step.allCases.count)"))
    }

    /// Smaller at the accessibility text sizes, so the words get the room.
    private var animationSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 110 : 150
    }

    private func header(_ animation: OnboardingAnimation, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        VStack(spacing: 16) {
            OnboardingAnimationView(animation: animation, size: animationSize, tint: accent)
                .padding(.top, 8)

            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

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
            header(.welcome, title: "Onboarding.welcome_title", body: "Onboarding.welcome_body")
            note("Onboarding.welcome_data", icon: "building.columns")
        case .location:
            locationStep
        case .closestStation:
            closestStationStep
        case .notifications:
            notificationsStep
        case .more:
            moreStep
        }
    }

    @ViewBuilder
    private var locationStep: some View {
        header(.location, title: "Onboarding.location_title", body: "Onboarding.location_body")

        switch viewModel.locationState {
        case .on:
            OnboardingSuccessNote(text: "Onboarding.location_on", tint: accent)
        case .off:
            note("Onboarding.location_off")
        case .notAsked, .asking:
            EmptyView()
        }
    }

    @ViewBuilder
    private var closestStationStep: some View {
        header(.closestStation, title: "Onboarding.closest_title", body: "Onboarding.closest_body")

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

                if !viewModel.stations.isEmpty {
                    Button {
                        showingStationPicker = true
                    } label: {
                        Label("Onboarding.choose_station", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(accent)
                }

                if let model = viewModel.stationModel {
                    OnboardingFavouriteStatus(model: model, tint: accent)
                }
            }
        }
        .onAppear(perform: viewModel.loadClosestStation)
    }

    @ViewBuilder
    private var notificationsStep: some View {
        header(.notifications, title: "Onboarding.notifications_title", body: "Onboarding.notifications_body")

        switch viewModel.notificationState {
        case .on:
            OnboardingSuccessNote(text: "Onboarding.notifications_on", tint: accent)
        case .off:
            note("Onboarding.notifications_off")
        case .notAsked, .asking:
            note("Onboarding.dnd_after_notifications", icon: "moon")
        }

        if viewModel.showsQuietHours {
            OnboardingDoNotDisturb(viewModel: sharedDoNotDisturb ?? ownDoNotDisturb)
        }
    }

    @ViewBuilder
    private var moreStep: some View {
        header(.more, title: "Onboarding.more_title", body: "Onboarding.more_body")

        VStack(spacing: 12) {
            OnboardingMoreRow(
                icon: "rectangle.grid.2x2", color: AirStatuses.good,
                title: "Onboarding.more_widgets_title", detail: "Onboarding.more_widgets_body",
                action: { guide = .widgets }
            )
            OnboardingMoreRow(
                icon: "waveform", color: AirStatuses.unhealthyforsensitivegroup,
                title: "Onboarding.more_siri_title", detail: "Onboarding.more_siri_body",
                action: { guide = .shortcuts }
            )
            OnboardingMoreRow(
                icon: "calendar", color: AirStatuses.moderate,
                title: "Onboarding.more_forecast_title", detail: "Onboarding.more_forecast_body",
                action: nil
            )
        }

        OnboardingProSummary(isPro: settings.isPro, tint: accent)
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
        case .more:
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
        case .more where !settings.isPro:
            Button("Onboarding.see_pro_plans") {
                showingPro = true
                TrackingManager.logEvent(.onboardingOpenPro)
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

    private var shownStationId: Int? {
        if case .loaded(let shown) = viewModel.closest {
            return shown.pollutant.stationId
        }
        return nil
    }

    private func wideButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
    }

    private func finish(skippedAt step: Onboarding.Step? = nil) {
        viewModel.finish(skippedAt: step, isLaunchFlow: isLaunchFlow)
        onFinish()
    }
}

/// A permission granted or a station added: a check that draws itself, then
/// the words.
private struct OnboardingSuccessNote: View {
    var text: LocalizedStringKey
    var tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            OnboardingAnimationView(animation: .success, size: 32, tint: tint)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The suggested station's current AQI, with its face and level.
private struct OnboardingStationCard: View {
    var pollutant: Pollutant

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let value = pollutant.getValue(airIndexType: .aqi)
        let status = AirStatuses.checkAirStatus(airIndexType: .aqi, value: value)

        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Stacked, so the name and level aren't squeezed beside the badge.
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        face(status)
                        badge(value: value, status: status)
                    }
                    identity(status)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 14) {
                    face(status)
                    identity(status)
                    Spacer(minLength: 8)
                    badge(value: value, status: status)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func face(_ status: AirStatuses) -> some View {
        if status.hasFaceImage {
            Image(status.getImage())
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
        }
    }

    private func identity(_ status: AirStatuses) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: pollutant.displayName)
                .font(.title3.bold())
                .fixedSize(horizontal: false, vertical: true)
            if let locality = pollutant.displayLocality {
                Text(verbatim: locality)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(status.toString())
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func badge(value: Double, status: AirStatuses) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: "AQI")
                .font(.caption.bold())
            Text(verbatim: value != 0 ? value.format(f: AirIndexTypes.aqi.getFormat()) : "-")
                .font(.title.bold())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .foregroundColor(Color(status.getForegroundColor()))
        .frame(minWidth: 72, minHeight: 72)
        .background(Color(status.getColor()))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// What adding the suggested station did, as the station screen reports it:
/// a favourite, and its alerts on with it (FOX-31).
private struct OnboardingFavouriteStatus: View {
    @ObservedObject var model: DetailsViewModel
    var tint: Color

    var body: some View {
        if model.isFavourited {
            VStack(alignment: .leading, spacing: 8) {
                OnboardingSuccessNote(text: "Onboarding.in_favourites", tint: tint)
                Group {
                    if model.hasAlerts {
                        Label("Onboarding.alerts_now_on", systemImage: "bell.fill")
                    } else if model.favouriteAlertsHint == .capReached {
                        Label("Favourites.alerts_cap_reached_message \(FavouriteAlerts.maxAlertedStations)", systemImage: "bell.slash")
                            .foregroundColor(.secondary)
                    } else if model.favouriteAlertsHint == .notificationsDenied {
                        Label("Onboarding.alerts_need_notifications", systemImage: "bell.slash")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Every station with its current AQI, to search or browse by area.
private struct OnboardingStationPicker: View {
    var stations: Pollutants
    var selectedId: Int?
    var onPick: (Pollutant) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationView {
            List {
                ForEach(OnboardingStationList.sections(stations, matching: query), id: \.title) { section in
                    Section(header: Text(verbatim: section.title)) {
                        ForEach(section.stations, id: \.stationId) { station in
                            Button {
                                onPick(station)
                                dismiss()
                            } label: {
                                row(station)
                            }
                            .accessibilityAddTraits(station.stationId == selectedId ? .isSelected : [])
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: Text("DetailsList.search"))
            .navigationBarTitle(Text("Onboarding.choose_station_title"), displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Onboarding.cancel") { dismiss() }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func row(_ station: Pollutant) -> some View {
        HStack(spacing: 8) {
            if station.stationId == selectedId {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.accentColor)
                    .accessibilityHidden(true)
            }
            StationRow(
                title: station.displayName,
                subtitle: station.displayLocality,
                reading: .init(aqi: station.aqi)
            )
        }
        .foregroundColor(.primary)
    }
}

/// The Help entries the last step links to.
enum OnboardingGuide: String, Identifiable {
    case widgets
    case shortcuts

    var id: String { rawValue }
}

/// A Help entry over the flow, closed back onto it.
private struct OnboardingGuideSheet: View {
    var guide: OnboardingGuide

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                switch guide {
                case .widgets: WidgetGuideView()
                case .shortcuts: ShortcutsGuideView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("Onboarding.close"))
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

/// One thing the app does outside the app, with how to add it.
private struct OnboardingMoreRow: View {
    var icon: String
    var color: AirStatuses
    var title: LocalizedStringKey
    var detail: LocalizedStringKey
    /// Opens the matching Help entry; nil when the detail says it all.
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) {
                content(showsLink: true)
            }
            .buttonStyle(.plain)
        } else {
            content(showsLink: false)
                .accessibilityElement(children: .combine)
        }
    }

    private func content(showsLink: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(Color(color.getForegroundColor()))
                .frame(width: 40, height: 40)
                .background(Color(color.getColor()))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if showsLink {
                    Text("Onboarding.how_to_add")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.accentColor)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// Pro on the last step: what stays free, what Pro adds, and the real prices
/// and trial from the App Store. Buying happens on the Pro screen only.
private struct OnboardingProSummary: View {
    var isPro: Bool
    var tint: Color

    struct Plan: Identifiable {
        let id: String
        let name: String
        let price: String
        let trial: OnboardingProTrial?
    }

    @State private var plans: [Plan] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pro.title")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)

            if isPro {
                Label("Onboarding.premium_active", systemImage: "checkmark.seal")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Onboarding.premium_body")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                tagged("Onboarding.free_heading", color: Color(AirStatuses.good.getColor()))
                VStack(alignment: .leading, spacing: 8) {
                    freeRow("mic", "Onboarding.free_siri")
                    freeRow("watchface.applewatch.case", "Onboarding.free_complication")
                    freeRow("arrow.triangle.2.circlepath", "Onboarding.free_index_cycling")
                }

                tagged("Onboarding.pro_heading", color: tint)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ProFeature.allCases) { feature in
                        ProFeatureRow(feature: feature)
                    }
                }

                prices
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            guard !isPro else { return }
            await load()
        }
    }

    private func tagged(_ title: LocalizedStringKey, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color))
            .foregroundColor(.white)
    }

    private func freeRow(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(Color(AirStatuses.good.getColor()))
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var prices: some View {
        if loading {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if !plans.isEmpty {
            VStack(spacing: 0) {
                ForEach(plans) { plan in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: plan.name)
                                .font(.subheadline.weight(.semibold))
                            if let trial = plan.trial {
                                trialText(trial)
                                    .font(.caption)
                                    .foregroundColor(Color(AirStatuses.good.getColor()))
                            }
                        }
                        Spacer(minLength: 8)
                        Text(verbatim: plan.price)
                            .font(.subheadline.weight(.semibold))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)

                    if plan.id != plans.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func trialText(_ trial: OnboardingProTrial) -> Text {
        switch trial.unit {
        case .days: return Text("Onboarding.pro_trial_days \(trial.count)")
        case .weeks: return Text("Onboarding.pro_trial_weeks \(trial.count)")
        case .months: return Text("Onboarding.pro_trial_months \(trial.count)")
        case .years: return Text("Onboarding.pro_trial_years \(trial.count)")
        }
    }

    /// The Pro screen's products. A trial shows only while the reader can
    /// still take it.
    private func load() async {
        defer { loading = false }
        guard let products = try? await IAPManager.products() else { return }
        var loaded: [Plan] = []
        for product in products {
            var trial: OnboardingProTrial?
            if let subscription = product.subscription,
               let offer = subscription.introductoryOffer,
               offer.paymentMode == .freeTrial,
               await subscription.isEligibleForIntroOffer {
                trial = OnboardingProTrial(unit: offer.period.unit, value: offer.period.value)
            }
            loaded.append(Plan(id: product.id, name: product.displayName, price: product.displayPrice, trial: trial))
        }
        plans = loaded
    }
}

/// Help's quiet-hours controls, written through Help's own model.
private struct OnboardingDoNotDisturb: View {
    @ObservedObject var viewModel: HelpViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Onboarding.dnd_title", systemImage: "moon.fill")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text("Onboarding.dnd_body")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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

            Text("Onboarding.dnd_footer")
                .font(.footnote)
                .foregroundColor(.secondary)
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
