//
//  StationPickerView.swift
//  TWAQIWatch
//
//  Created by kf on 20/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// Every station with its current AQI, so the list doubles as an overview.
struct StationPickerView: View {
    @ObservedObject var model: WatchModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List {
            // Home: the closest station, or the 中正 default without a location.
            if query.isEmpty {
                Button {
                    model.pin(nil)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Label("Watch.closest", systemImage: "location.fill")

                            // Which station that is right now, on its own line:
                            // the watch is too narrow for it in brackets.
                            if let home = model.home {
                                Text(home.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if model.isHome {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            ForEach(filtered, id: \.stationId) { pollutant in
                Button {
                    model.pin(pollutant)
                    dismiss()
                } label: {
                    row(pollutant)
                }
            }
        }
        .overlay {
            if model.stations.isEmpty {
                if model.failed {
                    VStack(spacing: 8) {
                        Text("Watch.loading_failed")
                            .multilineTextAlignment(.center)

                        Button("Watch.retry") {
                            Task { await model.loadStations() }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .searchable(text: $query)
        .navigationTitle(Text("Watch.stations"))
        .task {
            if model.stations.isEmpty {
                await model.loadStations()
            }
        }
    }

    private func row(_ pollutant: Pollutant) -> some View {
        let status = AirStatuses.checkAirStatus(airIndexType: .aqi, value: pollutant.aqi)

        return HStack {
            Circle()
                .fill(Color(status.getColor()))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading) {
                Text(name(pollutant))

                if let locality = locality(pollutant) {
                    Text(locality)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !model.isHome && model.reading?.stationId == pollutant.stationId {
                Image(systemName: "checkmark")
            } else {
                Text(pollutant.aqi.format(f: AirIndexTypes.aqi.getFormat()))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Matches name in either language, county and township, like the iOS search.
    private var filtered: Pollutants {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return model.stations }

        return model.stations.filter { pollutant in
            [pollutant.name, pollutant.nameLocal, pollutant.county, pollutant.countyLocal, pollutant.township]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(needle) }
        }
    }

    private func name(_ pollutant: Pollutant) -> String {
        WatchReading.displayName(
            name: pollutant.name,
            nameLocal: pollutant.nameLocal,
            code: pollutant.code,
            id: pollutant.stationId
        )
    }

    private func locality(_ pollutant: Pollutant) -> String? {
        let value = Locale.isChinese ? pollutant.countyLocal : pollutant.county
        return (value?.isEmpty ?? true) ? nil : value
    }
}
