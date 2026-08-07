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
            }
            .navigationBarTitle("Help.help")
            .safeAreaInset(edge: .bottom) {
                AdBannerView(adUnitID: getEnv("AdUnitIdHelpFooter")!)
            }
            .onAppear {
                IAPManager.shared.fetchAvailableProducts()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
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
            Button(action: settings.unlockPro) {
                Text("Help.ad_free")
            }

            Button(action: settings.restorePurchase) {
                Text("Help.restore_purchase")
                    .foregroundColor(.secondary)
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
                externalLink(title: definitionPage.title, url: definitionPage.url) {
                    TrackingManager.logEvent(
                        eventName: "open_definition_link",
                        parameters: ["label": definitionPage.rawValue]
                    )
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
        }
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
