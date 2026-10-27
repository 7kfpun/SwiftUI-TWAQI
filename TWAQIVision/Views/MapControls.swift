//
//  MapControls.swift
//  TWAQIVision
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// The ornament under the volume, standing in for the iOS map's controls:
/// which index the pins show, wind mode, my location, the colour key and
/// freshness — plus the ways into the station browser and the tabletop.
struct MapControls: View {
    @Environment(StationStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Picker("Vision.index", selection: $store.index) {
                    ForEach(AirIndexTypes.allCases, id: \.self) { type in
                        Text(verbatim: type.toString()).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 460)

                Toggle(isOn: $store.isWindMode) {
                    Label("Vision.wind", systemImage: "wind")
                }
                .toggleStyle(.button)

                Button {
                    Task { await store.selectNearest() }
                } label: {
                    Label("Vision.nearest", systemImage: "location")
                }
                .disabled(store.isLocating)

                Button {
                    openWindow(single: BrowserView.id)
                } label: {
                    Label("Vision.stations", systemImage: "list.bullet")
                }

                // Shows whether the tabletop is actually out — the tabletop
                // view reports that itself, so a close from the system
                // (the Digital Crown) is reflected too. The toggle only asks.
                Toggle(isOn: Binding(
                    get: { store.isTabletopOpen },
                    set: { open in
                        Task {
                            if open {
                                _ = await openImmersiveSpace(id: TWAQIVisionApp.tabletopId)
                            } else {
                                await dismissImmersiveSpace()
                            }
                        }
                    }
                )) {
                    Label("Vision.tabletop", systemImage: "cube.transparent")
                }
                .toggleStyle(.button)
            }
            .labelStyle(.iconOnly)

            HStack(spacing: 20) {
                legend
                freshness
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("Vision.refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(store.loadState == .loading)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .glassBackgroundEffect()
    }

    @ViewBuilder private var freshness: some View {
        switch store.loadState {
        case .loading where store.stations.isEmpty:
            ProgressView()
        case .failed:
            Label("Vision.offline", systemImage: "wifi.exclamationmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            if let time = store.latestPublishTime {
                Text(time.asPublishDateTime)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(AirStatuses.getShowAllCases(), id: \.self) { status in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(status.getColor()))
                        .frame(width: 10, height: 10)
                    Text(status.toString())
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
