//
//  HelpView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct HelpView: View {
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject var viewModel: HelpViewModel

    @State private var showingPro = false
    @State private var versionTapCount = 0
    @State private var analyticsExcluded = TrackingManager.isExcluded
    @State private var proOverride = IAPManager.proOverride
    @State private var isTestEnvironment = false

    /// Revealed by tapping the version row 7 times; per device, not synced.
    @AppStorage("developerMode") private var developerMode = false

    var body: some View {
        NavigationView {
            Form {
                doNotDisturbSection

                if !settings.isPro {
                    purchaseSection
                }

                contactSection
                definitionSection
                aboutSection

                if developerMode {
                    developerSection
                }
            }
            .navigationBarTitle("Help.help")
            .safeAreaInset(edge: .bottom) {
                AdBannerView(adUnitID: getEnv("AdUnitIdHelpFooter")!)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showingPro) {
            ProView()
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
            ForEach(LinkPages.allCases) { linkPage in
                externalLink(title: linkPage.title, url: linkPage.url) {
                    TrackingManager.logEvent(
                        eventName: "open_contact_us_link",
                        parameters: ["label": linkPage.rawValue]
                    )
                }
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

    private var aboutSection: some View {
        Section(footer: Text("Help.data_provided_by_government").fontWeight(.light)) {
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

    /// Row that opens a web page, with a consistent trailing affordance.
    private func externalLink(
        title: LocalizedStringKey,
        url: URL,
        onOpen: @escaping () -> Void
    ) -> some View {
        Button(action: {
            UIApplication.shared.open(url)
            onOpen()
        }) {
            HStack {
                Text(title)
                    .foregroundColor(.primary)
                    .fontWeight(.light)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
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
