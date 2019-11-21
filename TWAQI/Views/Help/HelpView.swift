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

    @State var linkPage: LinkPages?
    @State var definitionPage: DefinitionPages?

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
                                // setting a new value to self.linkPage
                                // this is used for triggering the SafariView presentation through .sheet()
                                self.linkPage = linkPage
                                TrackingManager.logEvent(eventName: "open_contact_us_link", parameters: ["label": linkPage.rawValue])
                            }) {
                                Text(linkPage.title)
                                    .foregroundColor(Color.primary)
                                    .fontWeight(.light)
                                    .padding(.vertical, 10)
                            }
                        }
                    }
                    .sheet(item: $linkPage, content: { linkPage in
                        SafariView(url: linkPage.url)
                    })

                    Section(header: Text("Help.definition")) {
                        ForEach(DefinitionPages.allCases) { definitionPage in
                            Button(action: {
                                // setting a new value to self.linkPage
                                // this is used for triggering the SafariView presentation through .sheet()
                                self.definitionPage = definitionPage
                                TrackingManager.logEvent(eventName: "open_definition_link", parameters: ["label": definitionPage.rawValue])
                            }) {
                                Text(definitionPage.title)
                                    .foregroundColor(Color.primary)
                                    .fontWeight(.light)
                                    .padding(.vertical, 10)
                            }
                        }
                    }
                    .sheet(item: $definitionPage, content: { definitionPage in
                        SafariView(url: definitionPage.url)
                    })

                    Spacer().frame(height: 50)
                }

                AdBannerView(adUnitID: getEnv("AdUnitIdHelpFooter")!)
            }
            .onAppear {
                IAPManager.shared.fetchAvailableProducts()
            }
            .navigationBarTitle("Help.help")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct HelpView_Previews: PreviewProvider {
    static var previews: some View {
        HelpView(viewModel: .init()).environmentObject(SettingsStore())
    }
}
