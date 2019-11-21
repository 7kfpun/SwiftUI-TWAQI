//
//  MainView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct MainView: View {
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        ZStack {
            GoogleMapController()
                .edgesIgnoringSafeArea(.all)

            if !viewModel.isLoading {
                if viewModel.isShowCustomAd {
                    CustomAdView(customAd: viewModel.customAd)
                } else {
                    AdBannerView(adUnitID: getEnv("AdUnitIdMainFooter")!)
                }
            }
        }.onAppear(perform: getData)
    }

    private func getData() {
        self.viewModel.getData()
        self.viewModel.loadOneSignalSettings()
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        ForEach(["iPhone SE", "iPhone XS Max"], id: \.self) { deviceName in
            MainView(viewModel: .init())
                .environmentObject(SettingsStore())
                .previewDevice(PreviewDevice(rawValue: deviceName))
                .previewDisplayName(deviceName)
        }
    }
}
