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
/// read it; pinch and drag over the sea to turn the island.
struct TaiwanMapView: View {
    let layout: MapLayout

    @Environment(StationStore.self) private var store
    @Environment(Favourites.self) private var favourites
    @Environment(\.openWindow) private var openWindow
    @State private var scene = MapScene()
    @State private var loadFailed = false

    private static let cardId = "card"

    var body: some View {
        RealityView { content, attachments in
            content.add(scene.root)
            do {
                try await scene.load(layout: layout)
            } catch {
                loadFailed = true
            }
            if let card = attachments.entity(for: Self.cardId) {
                scene.attachCard(card)
            }
        } update: { _, _ in
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
        .overlay {
            if loadFailed {
                ContentUnavailableView("Vision.map_unavailable", systemImage: "map")
            }
        }
    }
}
