//
//  MainView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct MainView: View {
    var body: some View {
        GoogleMapController()
            .edgesIgnoringSafeArea(.all)
            .safeAreaInset(edge: .bottom) {
                AdBannerView(adUnitID: getEnv("AdUnitIdMainFooter")!)
            }
    }

}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        ForEach(["iPhone SE", "iPhone XS Max"], id: \.self) { deviceName in
            MainView()
                .previewDevice(PreviewDevice(rawValue: deviceName))
                .previewDisplayName(deviceName)
        }
    }
}
