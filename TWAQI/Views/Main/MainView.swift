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
    @Environment(\.foldLineX) private var foldLineX

    /// Station shown in the panel beside the map, in a wide window: iPad, an
    /// unfolded iPhone Duo, a large split-screen window.
    @State private var panelStationId: Int?

    /// Station shown in a sheet over the map, in a narrow window.
    @State private var sheetStation: SheetStation?

    private var isWide: Bool { horizontalSizeClass == .regular }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                map

                if isWide, let stationId = panelStationId {
                    Divider()
                        .edgesIgnoringSafeArea(.vertical)

                    stationPage(stationId: stationId) {
                        withAnimation { panelStationId = nil }
                    }
                    .frame(width: panelWidth(in: geometry.frame(in: .global)))
                    .transition(.move(edge: .trailing))
                }
            }
        }
        .sheet(item: $sheetStation) { station in
            stationPage(stationId: station.id) { sheetStation = nil }
        }
        // Folding or unfolding the Duo, or resizing the window, keeps the open
        // station open: the panel becomes a sheet, and the sheet the panel.
        .onChange(of: horizontalSizeClass) { sizeClass in
            if sizeClass == .regular, let station = sheetStation {
                sheetStation = nil
                panelStationId = station.id
            } else if sizeClass != .regular, let stationId = panelStationId {
                panelStationId = nil
                sheetStation = SheetStation(id: stationId)
            }
        }
    }

    private var map: some View {
        GoogleMapController(
            onStationSelected: { stationId in
                if isWide {
                    withAnimation { panelStationId = stationId }
                } else {
                    sheetStation = SheetStation(id: stationId)
                }
            },
            panelStationId: isWide ? panelStationId : nil
        )
            .edgesIgnoringSafeArea(.all)
            .safeAreaInset(edge: .bottom) {
                AdBannerView(adUnitID: getEnv("AdUnitIdMainFooter")!)
            }
    }

    /// The same page in the panel and the sheet, closed by the cross at its
    /// leading edge.
    private func stationPage(stationId: Int, onClose: @escaping () -> Void) -> some View {
        NavigationView {
            DetailsView(stationId: stationId, onClose: onClose)
                // A fresh page per station, not the last one's data reused.
                .id(stationId)
                .navigationBarTitleDisplayMode(.inline)
                .environmentObject(settings)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    /// On an unfolded foldable the divider sits on the fold, so the map and
    /// the station each get a half to themselves. Otherwise about two fifths
    /// of the window, so the map stays the larger part.
    private func panelWidth(in frame: CGRect) -> CGFloat {
        if let mapWidth = FoldLine.leadingWidth(foldX: foldLineX, in: frame) {
            return frame.width - mapWidth
        }
        return min(max(frame.width * 0.4, 320), 440)
    }

    private struct SheetStation: Identifiable {
        let id: Int
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
