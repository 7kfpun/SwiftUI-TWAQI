//
//  PollutantGridView.swift
//  TWAQI
//
//  Created by kf on 8/8/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// The six measured pollutants, all visible at once and each tappable to drive
/// the 24-hour chart.
///
/// Selection is a binding owned by the station screen, not the global
/// `airIndexTypeSelected` the old segmented picker wrote to — changing the
/// chart here must not re-score every marker on the map.
struct PollutantGridView: View {
    var pollutant: Pollutant
    @Binding var selected: AirIndexTypes

    private static let rows: [[AirIndexTypes]] = [
        [.pm25, .pm10, .o3],
        [.no2, .so2, .co],
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Details.pollutants")

            VStack(spacing: 8) {
                ForEach(Array(Self.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        ForEach(row, id: \.self) { cell($0) }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    /// One pollutant. Several stations report 0.0 for what they don't measure,
    /// so zero shows as an em dash rather than a falsely perfect reading — and
    /// the cell isn't tappable, because there is no history to chart.
    private func cell(_ type: AirIndexTypes) -> some View {
        let value = pollutant.getValue(airIndexType: type)
        let hasReading = value > 0
        let status = AirStatuses.checkAirStatus(airIndexType: type, value: value)
        let isSelected = selected == type

        return Button {
            // Tapping the selected pollutant again returns the chart to AQI, so
            // there is always a way back without a separate control.
            selected = isSelected ? .aqi : type
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(type.toString())
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(hasReading ? value.format(f: type.getFormat()) : "—")
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundColor(hasReading ? Color(status.getColor()) : .secondary)

                    if hasReading {
                        Text(type.getUnit())
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected
                        ? Color(status.getColor()).opacity(0.16)
                        : Color.secondary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color(status.getColor()) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!hasReading)
    }
}
