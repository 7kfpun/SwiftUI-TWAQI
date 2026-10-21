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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Station shown in the panel beside the map. Only used in a wide window
    /// (iPad, an unfolded foldable, a large split-screen window); a narrow one
    /// opens the station in a sheet over the map instead.
    @State private var selectedStationId: Int?

    private var isWide: Bool { horizontalSizeClass == .regular }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                map

                if isWide, let stationId = selectedStationId {
                    Divider()
                        .edgesIgnoringSafeArea(.vertical)

                    stationPanel(stationId: stationId)
                        .frame(width: Self.panelWidth(for: geometry.size.width))
                        .transition(.move(edge: .trailing))
                }
            }
        }
    }

    private var map: some View {
        GoogleMapController(onStationSelected: isWide ? { stationId in
            withAnimation { selectedStationId = stationId }
        } : nil)
            .edgesIgnoringSafeArea(.all)
            .safeAreaInset(edge: .bottom) {
                AdBannerView(adUnitID: getEnv("AdUnitIdMainFooter")!)
            }
    }

    private func stationPanel(stationId: Int) -> some View {
        NavigationView {
            DetailsView(stationId: stationId) {
                withAnimation { selectedStationId = nil }
            }
            // A fresh page per station, not the last one's data reused.
            .id(stationId)
            .navigationBarTitleDisplayMode(.inline)
            .environmentObject(settings)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    /// About two fifths of the window, so the map stays the larger half.
    private static func panelWidth(for width: CGFloat) -> CGFloat {
        min(max(width * 0.4, 320), 440)
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        ForEach(["iPhone SE", "iPhone XS Max"], id: \.self) { deviceName in
            MainView()
                .environmentObject(SettingsStore())
                .previewDevice(PreviewDevice(rawValue: deviceName))
                .previewDisplayName(deviceName)
        }
    }
}
