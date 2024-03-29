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
            ZStack {
                Form {
                    Section(header: Text("Help.do_not_disturb")) {
                        Toggle(isOn: $viewModel.isDndEnabled.animation()) {
                            Text("Help.turn_on_do_not_disturb")
                                .bold()
                        }
                        .padding(.vertical, 10)

                        if viewModel.isDndEnabled {
                            DatePicker(
                                selection: $viewModel.dndStartTime,
                                displayedComponents: .hourAndMinute,
                                label: { Text("Help.start_time").fontWeight(.light) }
                            )
                            .padding(.vertical, 10)

                            DatePicker(
                                selection: $viewModel.dndEndTime,
                                displayedComponents: .hourAndMinute,
                                label: { Text("Help.end_time").fontWeight(.light) }
                            )
                            .padding(.vertical, 10)
                        }

                        Button(action: {
                            self.viewModel.removeAllNotification()
                        }) {
                            Text("Help.cancel_site_notification")
                        }
                        .alert(isPresented: $viewModel.showingAlert) {
                            Alert(
                                title: Text("Help.all_site_notification_has_been_cancelled"),
                                dismissButton: .default(Text("OK"))
                            )
                        }
                    }

                    if !settings.isPro {
                        Section(header: Text("Help.in_app_purchase")) {
                            Button(action: {
                                self.settings.unlockPro()
                            }) {
                                Text("Help.ad_free")
                            }

                            Button(action: {
                                self.settings.restorePurchase()
                            }) {
                                Text("Help.restore_purchase")
                            }
                        }
                    }

                    Section(header: Text("Help.contact_us")) {
                        ForEach(LinkPages.allCases) { linkPage in
                            Button(action: {
                                UIApplication.shared.open(linkPage.url)
                                TrackingManager.logEvent(eventName: "open_contact_us_link", parameters: ["label": linkPage.rawValue])
                            }) {
                                Text(linkPage.title)
                                    .foregroundColor(Color.primary)
                                    .fontWeight(.light)
                                    .padding(.vertical, 10)
                            }
                        }
                    }

                    Section(header: Text("Help.definition")) {
                        ForEach(DefinitionPages.allCases) { definitionPage in
                            Button(action: {
                                UIApplication.shared.open(definitionPage.url)
                                TrackingManager.logEvent(eventName: "open_definition_link", parameters: ["label": definitionPage.rawValue])
                            }) {
                                Text(definitionPage.title)
                                    .foregroundColor(Color.primary)
                                    .fontWeight(.light)
                                    .padding(.vertical, 10)
                            }
                        }
                    }

                    Section {
                        Text("Help.data_provided_by_government")
                            .fontWeight(.light)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.bottom, 50)

                AdBannerView(adUnitID: getEnv("AdUnitIdHelpFooter")!)
            }
            .onAppear {
                IAPManager.shared.fetchAvailableProducts()
            }
            .navigationBarTitle("Help.help")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func submitImpressionEvent() {
        if viewModel.isShowCustomAd {
            if let customAd = viewModel.customAd {
                var components = URLComponents(string: customAd.imageUrl)!
                components.query = nil

                TrackingManager.logEvent(eventName: "ad_custom_impression", parameters: [
                    "name": customAd.name,
                    "position": customAd.position,
                    "impressionRate": customAd.impressionRate,
                    "imageUrl": "\(components.url!)",
                    "destinationUrl": customAd.destinationUrl,
                    "cpc": customAd.cpc,
                ])

                TrackingManager.logEvent(eventName: "ad_custom_\(customAd.name)_impression", parameters: [
                    "name": customAd.name,
                    "position": customAd.position,
                    "impressionRate": customAd.impressionRate,
                    "imageUrl": "\(components.url!)",
                    "destinationUrl": customAd.destinationUrl,
                    "cpc": customAd.cpc,
                ])
            }
        }
    }
}

struct HelpView_Previews: PreviewProvider {
    static var previews: some View {
        HelpView(viewModel: .init()).environmentObject(SettingsStore())
    }
}
