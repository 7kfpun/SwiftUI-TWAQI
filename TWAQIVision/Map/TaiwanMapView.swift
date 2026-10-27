//
//  TaiwanMapView.swift
//  TWAQIVision
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import RealityKit
import SwiftUI

/// The 3D island with a glowing pin per station. Look at a pin and pinch to
/// read it; pinch and drag over the sea to turn the island; pinch with both
/// hands to zoom.
struct TaiwanMapView: View {
    let layout: MapLayout

    @Environment(StationStore.self) private var store
    @Environment(Favourites.self) private var favourites
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene = MapScene()
    @State private var isLoading = true
    @State private var loadFailed = false

    private static let cardId = "card"

    var body: some View {
        RealityView { content, attachments in
            content.add(scene.root)
            if let card = attachments.entity(for: Self.cardId) {
                scene.attachCard(card)
            }
            // Not awaited: visionOS holds its launch placeholder until this
            // closure returns, which hid the loading placard and the opening.
            Task {
                do {
                    try await scene.load(layout: layout, reduceMotion: reduceMotion)
                } catch {
                    loadFailed = true
                }
                withAnimation(.easeOut(duration: 0.4)) { isLoading = false }
            }
        } update: { _, _ in
            // Re-run once the island exists, to place the pins on it.
            _ = isLoading
            if layout == .volume {
                scene.root.isEnabled = !store.isTabletopOpen
            }
            // Read here so SwiftUI re-runs this closure when any of them change.
            scene.apply(
                stations: store.stations,
                index: store.index,
                isWindMode: store.isWindMode,
                favourites: favourites.stationIds,
                userLocation: store.userLocation,
                selectedStationId: store.selectedStationId
            )
        } attachments: {
            Attachment(id: Self.cardId) {
                if let station = store.selectedStation {
                    StationCard(
                        station: station,
                        index: store.index,
                        isPinned: favourites.contains(station.stationId),
                        onTogglePin: { favourites.toggle(station.stationId) },
                        onOpen: { openWindow(id: StationWindow.id, value: station.stationId) },
                        onClose: { store.selectedStationId = nil }
                    )
                }
            }
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    let id = MapScene.stationId(for: value.entity)
                    // A pinch on the sea, or on the open pin again, puts the card away.
                    store.selectedStationId = id == store.selectedStationId ? nil : id
                }
        )
        .gesture(
            DragGesture(minimumDistance: 8)
                .targetedToAnyEntity()
                .onChanged { value in scene.rotate(by: value.translation) }
                .onEnded { _ in scene.endRotation() }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    let anchor = value.convert(value.startLocation3D, from: .local, to: scene.root)
                    scene.magnify(by: value.magnification, around: anchor)
                }
                .onEnded { _ in scene.endMagnify() }
        )
        .overlay {
            if loadFailed {
                ContentUnavailableView("Vision.map_unavailable", systemImage: "map")
            } else if isLoading, layout == .volume {
                LoadingPlacard()
                    .transition(.opacity)
            }
        }
    }
}

/// Shown in the volume while the island is built, in place of an empty box.
private struct LoadingPlacard: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "aqi.medium")
                .font(.system(size: 44))
                .symbolEffect(.pulse)
            Text(verbatim: Locale.isChinese ? "台灣空氣品質" : "Taiwan Air")
                .font(.title.bold())
            ProgressView()
        }
        .padding(32)
        .glassBackgroundEffect()
    }
}
