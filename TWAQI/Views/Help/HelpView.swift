//
//  HelpView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import GoogleMobileAds
import SwiftUI

struct HelpView: View {
    @EnvironmentObject var settings: SettingsStore

    @State var linkPage: Constants.LinkPages?

    var body: some View {
        NavigationView {
            ZStack {
                Form {
                    Section(header: Text("Do Not Disturb")) {
                        Toggle(isOn: $settings.isDndEnabled.animation()) {
                            Text("Turn on Do Not Disturb")
                                .bold()
                        }

                        if settings.isDndEnabled {
                            DatePicker(
                                selection: $settings.startDate,
                                displayedComponents: .hourAndMinute,
                                label: { Text("Start Date").fontWeight(.light) }
                            )

                            DatePicker(
                                selection: $settings.endDate,
                                displayedComponents: .hourAndMinute,
                                label: { Text("End Date").fontWeight(.light) }
                            )
                        }
                    }

                    if !settings.isPro {
                        Section {
                            Button(action: {
                                self.settings.unlockPro()
                            }) {
                                Text("Unlock PRO")
                            }

                            Button(action: {
                                self.settings.restorePurchase()
                            }) {
                                Text("Restore purchase")
                            }
                        }
                    }

                    Section {
                        ForEach(Constants.LinkPages.allCases) { linkPage in
                            Button(action: {
                                // setting a new value to self.linkPage
                                // this is used for triggering the SafariView presentation through .sheet()
                                self.linkPage = linkPage
                            }) {
                                Text(linkPage.title)
                                    .foregroundColor(Color.primary)
                                    .fontWeight(.light)
                            }
                        }
                    }
                    .sheet(item: $linkPage, content: { linkPage in
                        SafariView(url: linkPage.url)
                    })

                }

                VStack {
                    Spacer()
                    GADBannerViewController(adUnitID: getEnv("AdUnitIdHelpFooter")!)
                        .frame(width: kGADAdSizeBanner.size.width, height: kGADAdSizeBanner.size.height)
                }
            }
            .navigationBarTitle("Help")
        }
    }
}

struct HelpView_Previews: PreviewProvider {
    static var previews: some View {
        HelpView().environmentObject(SettingsStore())
    }
}
