//
//  MainView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import GoogleMobileAds
import SwiftUI

struct MainView: View {
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject var viewModel: MainViewModel

    @State var selectedLandmark: Landmark?

    var body: some View {
        ZStack {
//            MapView(
//                landmarks: $viewModel.landmarks,
//                selectedLandmark: $selectedLandmark
//            ).edgesIgnoringSafeArea(.vertical)

            GoogleMapView(pollutants: viewModel.pollutants, isWindMode: self.settings.isWindMode)
                .edgesIgnoringSafeArea(.vertical)

            VStack {
                Text(String(viewModel.count))

                HStack {
                    VStack {
                        Spacer()

                        Button(action: {
                            self.settings.isWindMode.toggle()
                        }) {
                            Image(systemName: "wind")
                                .frame(width: 60.0, height: 60.0)
                                .background(Color.white)
                                .foregroundColor(Color(0x5AC8FA))
                                .clipShape(Circle())
                                .shadow(radius: 2)
                        }
                    }

                    Spacer()

                    VStack {
                        Spacer()

                        button(for: "square.and.arrow.up.fill")
                        button(for: "viewfinder")
                        button(for: "paperplane.fill")
                    }
                }
                .padding()

                IndexSelector()

                GADBannerViewController(adUnitID: getEnv("AdUnitIdMainFooter")!)
                    .frame(width: kGADAdSizeBanner.size.width, height: kGADAdSizeBanner.size.height)
            }
        }
        .onAppear(perform: getData)
    }

    private func getData() {
        self.viewModel.getData()
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView(viewModel: .init())
            .environmentObject(SettingsStore())
    }
}
