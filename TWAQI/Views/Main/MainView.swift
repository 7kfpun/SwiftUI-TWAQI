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

            AdBannerView(adUnitID: getEnv("AdUnitIdMainFooter")!)
        }
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
