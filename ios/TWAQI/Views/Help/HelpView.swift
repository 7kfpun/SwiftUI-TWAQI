//
//  HelpView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

/// The Help tab's sections, top to bottom.
enum HelpSection: String, CaseIterable, Identifiable {
    case purchase
    case doNotDisturb
    case language
    case appearance
    case welcome
    case contact
    case privacy
    case widgetsAndWatch
    case definition
    case dataSources
    case about
    case developer

    var id: String { rawValue }

    /// Premium leads the list so free users see it first (FOX-68); Pro users
    /// don't get it. The developer section shows only in developer mode.
    /// Privacy settings show only where UMP requires the entry point (EEA, UK;
    /// FOX-118) and for free users, who are the ones asked.
    static func order(isPro: Bool, developerMode: Bool, privacyOptionsRequired: Bool = false) -> [HelpSection] {
        allCases.filter { section in
            switch section {
            case .privacy: return privacyOptionsRequired && !isPro
            case .purchase: return !isPro
            case .developer: return developerMode
            default: return true
            }
        }
    }
}

/// Every source the app shows data from, named once under Help → Data
/// sources rather than under each card (FOX-88). MOENV and CWA publish under
/// Taiwan's Open Government Data License 1.0, whose attribution asks for the
/// provider's name and the licence, not a credit on every screen.
enum DataSource: String, CaseIterable, Identifiable {
    case airQuality = "air_quality"
    case forecast
    case cams
    case weather
    case map

    var id: String { rawValue }

    /// What the app shows from it: "Air quality readings".
    var titleKey: String { "DataSources.\(rawValue)_title" }
    /// Who provides it, what it covers and how often it updates.
    var detailKey: String { "DataSources.\(rawValue)_detail" }

    var url: URL {
        switch self {
        case .airQuality: return URL(string: "https://airtw.moenv.gov.tw/")!
        case .forecast: return URL(string: "https://data.moenv.gov.tw/dataset/detail/AQF_P_01")!
        case .cams: return URL(string: "https://data.moenv.gov.tw/dataset/detail/AQX_P_01")!
        case .weather: return URL(string: "https://opendata.cwa.gov.tw/")!
        case .map: return URL(string: "https://maps.google.com/")!
        }
    }

    /// 政府資料開放授權條款－第1版, which MOENV and CWA open data use.
    static let licenceURL = URL(string: "https://data.gov.tw/license")!
}

struct HelpView: View {
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject var viewModel: HelpViewModel
    @ObservedObject private var consent = ConsentManager.shared

    @State private var showingPro = false
    @State private var showingOnboarding = false
    @State private var versionTapCount = 0
    @State private var analyticsExcluded = TrackingManager.isExcluded
    @State private var proOverride = IAPManager.proOverride
    @State private var isTestEnvironment = false

    /// Revealed by tapping the version row 7 times; per device, not synced.
    @AppStorage("developerMode") private var developerMode = false

    var body: some View {
        // Feedback, the widget and watch guides and the index pages open
        // beside the list in a wide window, as stations do in the lists.
        AdaptiveNavigation(placeholderIcon: "questionmark.circle", placeholderMessage: "Help.select_a_topic") {
            Form {
                ForEach(HelpSection.order(isPro: settings.isPro, developerMode: developerMode, privacyOptionsRequired: consent.privacyOptionsRequired)) { section in
                    view(for: section)
                }
            }
            .navigationBarTitle("Help.help")
            .safeAreaInset(edge: .bottom) {
                AdBannerView(adUnitID: getEnv("AdUnitIdHelpFooter")!, placement: .help)
            }
        }
        .sheet(isPresented: $showingPro) {
            ProView(source: .helpRow)
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            // Help's own quiet-hours model, so its switch shows what the flow set.
            OnboardingView(doNotDisturb: viewModel) { showingOnboarding = false }
                .environment(\.locale, settings.appLanguage.locale())
        }
    }

    @ViewBuilder
    private func view(for section: HelpSection) -> some View {
        switch section {
        case .purchase: purchaseSection
        case .doNotDisturb: doNotDisturbSection
        case .language: languageSection
        case .appearance: appearanceSection
        case .welcome: welcomeSection
        case .contact: contactSection
        case .privacy: privacySection
        case .widgetsAndWatch: widgetsAndWatchSection
        case .definition: definitionSection
        case .dataSources: dataSourcesSection
        case .about: aboutSection
        case .developer: developerSection
        }
    }

    /// Runs the whole welcome flow again (FOX-34).
    private var welcomeSection: some View {
        Section(header: Label("Help.welcome", systemImage: "hand.wave")) {
            Button {
                showingOnboarding = true
                TrackingManager.logEvent(.onboardingOpenFromHelp)
            } label: {
                Text("Help.show_welcome_guide")
            }
        }
    }

    private var doNotDisturbSection: some View {
        Section(header: Label("Help.do_not_disturb", systemImage: "moon")) {
            Toggle(isOn: $viewModel.isDndEnabled.animation()) {
                Text("Help.turn_on_do_not_disturb")
            }

            if viewModel.isDndEnabled {
                DatePicker(
                    selection: $viewModel.dndStartTime,
                    displayedComponents: .hourAndMinute,
                    label: { Text("Help.start_time").fontWeight(.light) }
                )

                DatePicker(
                    selection: $viewModel.dndEndTime,
                    displayedComponents: .hourAndMinute,
                    label: { Text("Help.end_time").fontWeight(.light) }
                )
            }

            Button(action: viewModel.removeAllNotification) {
                Text("Help.cancel_site_notification")
                    .foregroundColor(.red)
            }
            .alert(isPresented: $viewModel.showingAlert) {
                Alert(
                    title: Text("Help.all_site_notification_has_been_cancelled"),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    /// Overrides the system language for this app. The root view applies it
    /// at once; see `ContentView`.
    private var languageSection: some View {
        Section(
            header: Label("Help.language", systemImage: "globe"),
            footer: Text("Help.language_footer").fontWeight(.light)
        ) {
            Picker(selection: Binding(
                get: { settings.appLanguage },
                set: { settings.appLanguage = $0 }
            )) {
                Text("Help.language_system").tag(AppLanguage.system)
                // Each language in its own name, whatever the UI language.
                Text(verbatim: "繁體中文").tag(AppLanguage.traditionalChinese)
                Text(verbatim: "English").tag(AppLanguage.english)
            } label: {
                Text("Help.language")
            }
        }
    }

    /// Light, dark, or following iOS (FOX-43). The setter restyles every
    /// open window; see `SettingsStore.appearance`.
    private var appearanceSection: some View {
        Section(header: Label("Help.appearance", systemImage: "circle.lefthalf.filled")) {
            Picker(selection: Binding(
                get: { settings.appearance },
                set: { settings.appearance = $0 }
            )) {
                Text("Help.appearance_system").tag(AppAppearance.system)
                Text("Help.appearance_light").tag(AppAppearance.light)
                Text("Help.appearance_dark").tag(AppAppearance.dark)
            } label: {
                Text("Help.appearance")
            }
        }
    }

    private var purchaseSection: some View {
        Section(header: Label("Help.in_app_purchase", systemImage: "sparkles")) {
            Button {
                showingPro = true
            } label: {
                Text("Help.ad_free")
            }
        }
    }

    private var contactSection: some View {
        Section(header: Label("Help.contact_us", systemImage: "envelope")) {
            NavigationLink(destination: FeedbackView()) {
                Text("Help.feedback_or_contact_us")
                    .fontWeight(.light)
            }

            NavigationLink(destination: CooperateView()) {
                Text("Help.interested_to_be_our_business_partner")
                    .fontWeight(.light)
            }
        }
    }

    private var privacySection: some View {
        Section(header: Label("Help.privacy", systemImage: "hand.raised")) {
            Button {
                consent.presentPrivacyOptions()
            } label: {
                Text("Help.privacy_settings")
                    .fontWeight(.light)
            }
        }
    }

    private var widgetsAndWatchSection: some View {
        Section(header: Label("Help.widgets_and_watch", systemImage: "square.grid.2x2")) {
            NavigationLink(destination: WidgetGuideView()) {
                Text("Help.widgets_title")
                    .fontWeight(.light)
            }

            NavigationLink(destination: WatchGuideView()) {
                Text("Help.watch_title")
                    .fontWeight(.light)
            }

            NavigationLink(destination: ShortcutsGuideView()) {
                Text("Help.shortcuts_title")
                    .fontWeight(.light)
            }
        }
    }

    private var definitionSection: some View {
        Section(header: Label("Help.definition", systemImage: "book")) {
            ForEach(DefinitionPages.allCases) { definitionPage in
                NavigationLink(destination: IndexGuideView(page: definitionPage)) {
                    Text(definitionPage.title)
                        .fontWeight(.light)
                }
            }
        }
    }

    /// Where each kind of data comes from, with a link to it (FOX-88). The
    /// screens themselves carry no source labels.
    private var dataSourcesSection: some View {
        Section(
            header: Label("DataSources.header", systemImage: "antenna.radiowaves.left.and.right"),
            footer: Text("DataSources.footer").fontWeight(.light)
        ) {
            ForEach(DataSource.allCases) { source in
                linkRow(
                    destination: source.url,
                    title: LocalizedStringKey(source.titleKey),
                    detail: LocalizedStringKey(source.detailKey)
                )
            }

            linkRow(destination: DataSource.licenceURL, title: "DataSources.licence_title", detail: nil)
        }
    }

    private func linkRow(destination: URL, title: LocalizedStringKey, detail: LocalizedStringKey?) -> some View {
        Link(destination: destination) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundColor(.primary)
                    if let detail {
                        Text(detail)
                            .font(.footnote.weight(.light))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text(verbatim: "Version")
                    .fontWeight(.light)
                Spacer()
                Text(verbatim: appVersion)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            // Tap 7 times to show or hide the developer section.
            .onTapGesture {
                versionTapCount += 1
                guard versionTapCount >= 7 else { return }
                versionTapCount = 0
                developerMode.toggle()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    /// For the developer's own devices, so unlocalized. Hidden until the version
    /// row is tapped 7 times.
    private var developerSection: some View {
        Section(
            header: Label(title: { Text(verbatim: "Developer") }, icon: { Image(systemName: "hammer") }),
            footer: Text(verbatim: isTestEnvironment
                ? "Pro override applies to this device only; the watch has its own."
                : "Pro override is only available in Debug and TestFlight builds.")
        ) {
            Toggle(isOn: Binding(
                get: { analyticsExcluded },
                set: { excluded in
                    analyticsExcluded = excluded
                    TrackingManager.setExcluded(excluded)
                }
            )) {
                Text(verbatim: "Exclude this device from analytics")
            }

            if isTestEnvironment {
                Picker(selection: Binding(
                    get: { proOverride },
                    set: { value in
                        proOverride = value
                        IAPManager.proOverride = value
                        Task { await SettingsStore.refreshPro() }
                    }
                )) {
                    Text(verbatim: "App Store").tag(IAPManager.ProOverride.appStore)
                    Text(verbatim: "Force Pro").tag(IAPManager.ProOverride.forcePro)
                    Text(verbatim: "Force Free").tag(IAPManager.ProOverride.forceFree)
                } label: {
                    Text(verbatim: "Pro")
                }
            }
        }
        .task { isTestEnvironment = await IAPManager.isTestEnvironment() }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

struct HelpView_Previews: PreviewProvider {
    static var previews: some View {
        HelpView(viewModel: .init()).environmentObject(SettingsStore())
    }
}
