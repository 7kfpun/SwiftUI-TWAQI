//
//  StationInfoView.swift
//  TWAQI
//
//  Created by kf on 8/8/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// Wind + location facts for a station. Everything is optional in the API, so
/// each row disappears rather than rendering an empty placeholder.
///
/// The pollutant readings moved to `PollutantGridView`, which sits directly
/// above the chart it drives — tapping a reading here to change a chart two
/// sections away read as unrelated.
struct StationInfoView: View {
    var pollutant: Pollutant

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            windSection

            if pollutant.address != nil || !pollutant.coordinateText.isEmpty {
                locationSection
            }
        }
        .padding(.horizontal)
    }

    private var windSection: some View {
        let wind = pollutant.wind

        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Details.conditions")

            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        .frame(width: 48, height: 48)

                    if wind.isCalm {
                        Text("—")
                            .font(.callout)
                            .fontWeight(.thin)
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Color(0x5AC8FA))
                            .rotationEffect(wind.arrowRotation)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Details.wind")
                        .font(.caption)
                        .fontWeight(.light)
                        .foregroundColor(.secondary)

                    if wind.isCalm {
                        Text("Wind.calm")
                            .font(.callout)
                    } else {
                        HStack(spacing: 6) {
                            Text(wind.compassPoint)
                                .font(.callout)
                                .fontWeight(.medium)
                            Text("\(wind.speed.format(f: ".1")) m/s")
                                .font(.callout)
                                .fontWeight(.thin)
                        }
                        Text(wind.toString())
                            .font(.caption)
                            .fontWeight(.light)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
        }
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Details.location")

            if let address = pollutant.address {
                InfoRow(icon: "mappin.circle", title: "Details.address", value: address)
            }

            InfoRow(icon: "location", title: "Details.coordinates", value: pollutant.coordinateText)
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

private struct InfoRow: View {
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
