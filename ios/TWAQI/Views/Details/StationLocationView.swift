//
//  StationLocationView.swift
//  TWAQI
//
//  Created by kf on 8/8/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// Where the monitoring station physically is.
///
/// Fixed metadata, not a reading — so it sits at the foot of the screen, below
/// everything that changes hour to hour, rather than sharing a heading with the
/// live wind measurement as it used to.
struct StationLocationView: View {
    var address: String?
    var coordinateText: String
    /// The address as it should read — translated on device outside Chinese.
    /// Nil shows `address`, the API's Chinese.
    var displayAddress: String?

    init(address: String?, coordinateText: String) {
        self.address = address
        self.coordinateText = coordinateText
    }

    init(pollutant: Pollutant) {
        self.init(address: pollutant.address, coordinateText: pollutant.coordinateText)
    }

    /// Nothing to show for a station the API gave no address or coordinates.
    var hasContent: Bool {
        address != nil || !coordinateText.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Details.location")

            if let address = displayAddress ?? address {
                InfoRow(icon: "mappin.circle", title: "Details.address", value: address)
            }

            if !coordinateText.isEmpty {
                InfoRow(
                    icon: "location",
                    title: "Details.coordinates",
                    value: coordinateText
                )
            }
        }
        .padding(.horizontal)
    }
}

struct InfoRow: View {
    var icon: String
    var title: LocalizedStringKey
    var value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.light)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.footnote)
                    .fontWeight(.light)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }
}

/// Small uppercase heading above a group of rows. Shared across the station
/// screen's sections so they all sit on the same visual rhythm.
struct SectionLabel: View {
    var text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
    }
}
