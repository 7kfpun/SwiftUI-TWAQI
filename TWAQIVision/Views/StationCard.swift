//
//  StationCard.swift
//  TWAQIVision
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// Floats over a selected pin: the headline reading for the chosen index,
/// then every pollutant the station measures.
///
/// Drag the card out of the volume to pin the station as its own window
/// anywhere in the room.
struct StationCard: View {
    let station: Pollutant
    let index: AirIndexTypes
    let isPinned: Bool
    let onTogglePin: () -> Void
    let onOpen: () -> Void
    let onClose: () -> Void

    private var value: Double { station.getValue(airIndexType: index) }
    private var status: AirStatuses { AirStatuses.checkAirStatus(airIndexType: index, value: value) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            headline
            pollutants
            footer
            actions
        }
        .padding(24)
        .frame(width: 360)
        .glassBackgroundEffect()
        .onDrag {
            StationActivity.itemProvider(stationId: station.stationId, title: station.displayName)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onTogglePin) {
                    Label(
                        isPinned ? "Vision.unpin" : "Vision.pin",
                        systemImage: isPinned ? "pin.slash" : "pin"
                    )
                }
                Button(action: onOpen) {
                    Label("Vision.details", systemImage: "macwindow")
                }
            }
            Text("Vision.drag_to_pin")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(station.displayName)
                    .font(.title2.bold())
                if let locality = station.displayLocality ?? station.displayArea {
                    Text(locality)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text("Vision.close"))
        }
    }

    private var headline: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(value.format(f: index.getFormat()))
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color(status.getForegroundColor()))
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(Color(status.getColor()), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(index.toString()) \(index.getUnit())")
                    .font(.headline)
                Text(status.toString())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pollutants: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
            let others = AirIndexTypes.allCases.filter { $0 != index }
            ForEach(Array(stride(from: 0, to: others.count, by: 2)), id: \.self) { start in
                GridRow {
                    ForEach(others[start..<min(start + 2, others.count)], id: \.self) { type in
                        reading(type)
                    }
                }
            }
        }
    }

    private func reading(_ type: AirIndexTypes) -> some View {
        let value = station.getValue(airIndexType: type)
        let status = AirStatuses.checkAirStatus(airIndexType: type, value: value)
        return HStack(spacing: 8) {
            Circle()
                .fill(Color(status.getColor()))
                .frame(width: 10, height: 10)
            Text(type.toString())
                .foregroundStyle(.secondary)
            Text(value.format(f: type.getFormat()))
                .monospacedDigit()
        }
        .font(.callout)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !station.wind.isCalm {
                Label {
                    Text("Details.wind") + Text(" · \(station.wind.compassPoint) \(station.windSpeed.format(f: ".1")) m/s")
                } icon: {
                    // As on the watch: a down arrow turned by the bearing the
                    // wind comes *from* points downwind.
                    Image(systemName: "arrow.down")
                        .rotationEffect(station.wind.arrowRotation)
                }
            }
            Label {
                Text("Details.last_updated") + Text(" · \(station.publishTime.asPublishDateTime)")
            } icon: {
                Image(systemName: "clock")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
