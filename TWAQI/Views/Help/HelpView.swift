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

    @State var linkPage: LinkPages?

    var body: some View {
        NavigationView {
            ZStack {
                Form {
                    Section(header: Text("Help.do_not_disturb")) {
                        Toggle(isOn: $settings.isDndEnabled.animation()) {
                            Text("Help.turn_on_do_not_disturb")
                                .bold()
                        }
                        .padding(.vertical, 10)

                        if settings.isDndEnabled {
                            DatePicker(
                                selection: $settings.startDate,
                                displayedComponents: .hourAndMinute,
                                label: { Text("Help.start_time").fontWeight(.light) }
                            )
                            .padding(.vertical, 10)

                            DatePicker(
                                selection: $settings.endDate,
                                displayedComponents: .hourAndMinute,
                                label: { Text("Help.end_time").fontWeight(.light) }
                            )
                            .padding(.vertical, 10)
                        }
                    }

                    if !settings.isPro {
                        Section {
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

                    Section {
                        ForEach(LinkPages.allCases) { linkPage in
                            Button(action: {
                                // setting a new value to self.linkPage
                                // this is used for triggering the SafariView presentation through .sheet()
                                self.linkPage = linkPage
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

                }
                .padding(.bottom, 50)

                AdBanner(adUnitID: getEnv("AdUnitIdHelpFooter")!)
            }
            .onAppear {
                IAPManager.shared.fetchAvailableProducts()
            }
            .navigationBarTitle("Help.help")
        }
    }
}

struct HelpView_Previews: PreviewProvider {
    static var previews: some View {
        HelpView().environmentObject(SettingsStore())
    }
}
