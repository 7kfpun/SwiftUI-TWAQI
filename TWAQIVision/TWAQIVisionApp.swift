//
//  TWAQIVisionApp.swift
//  TWAQIVision
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

@main
struct TWAQIVisionApp: App {
    static let mapId = "map"
    static let tabletopId = "tabletop"

    @State private var store = StationStore()
    @State private var favourites = Favourites()

    init() {
        StationComponent.registerComponent()
    }

    var body: some Scene {
        // First, so it's what the app opens with: the map is the iOS app's
        // first tab too.
        //
        // A plain group, unlike the browser's: keyed by a value, the launch
        // volume never got its content and sat on the system placeholder.
        // `StationStore.isMapOpen` keeps it to one instead.
        WindowGroup(id: Self.mapId) {
            TaiwanMapView(layout: .volume)
                #if DEBUG
                .modifier(ScreenshotLaunchModifier())
                #endif
                .environment(store)
                .environment(favourites)
                .ornament(attachmentAnchor: .scene(.bottomFront), contentAlignment: .top) {
                    MapControls()
                        .environment(store)
                }
                // Owned by the volume: it's the scene that's always open.
                .task { await store.keepFresh() }
                .onAppear { store.isMapOpen = true }
                .onDisappear { store.isMapOpen = false }
        }
        .windowStyle(.volumetric)
        .defaultSize(
            width: Double(VolumeSize.width), height: Double(VolumeSize.height), depth: Double(VolumeSize.depth),
            in: .meters
        )
        // Dropped stations go to their own windows, never into the map.
        .handlesExternalEvents(matching: [])

        // One of a kind: a plain WindowGroup opens another copy on every
        // `openWindow`, and `Window` needs visionOS 26. Keyed by a fixed
        // value, opening it again brings the open one forward. See
        // `OpenWindowAction.callAsFunction(single:)`.
        WindowGroup(id: BrowserView.id, for: String.self) { _ in
            BrowserView()
                .environment(store)
                .environment(favourites)
        } defaultValue: {
            BrowserView.id
        }
        .defaultSize(width: 720, height: 860)
        .handlesExternalEvents(matching: [])

        WindowGroup(id: StationWindow.id, for: Int.self) { $stationId in
            StationWindow(stationId: $stationId)
                .environment(store)
                .environment(favourites)
        }
        .defaultSize(width: 640, height: 900)
        .handlesExternalEvents(matching: [StationActivity.type])

        ImmersiveSpace(id: Self.tabletopId) {
            TaiwanMapView(layout: .tabletop)
                .environment(store)
                .environment(favourites)
                .onAppear { store.isTabletopOpen = true }
                .onDisappear { store.isTabletopOpen = false }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}

extension OpenWindowAction {
    /// Opens a one-of-a-kind window keyed by its own id, or brings the open
    /// one forward. Its group is keyed by a value that never changes, so
    /// there is only ever one window to match.
    @MainActor
    func callAsFunction(single id: String) {
        self(id: id, value: id)
    }
}
