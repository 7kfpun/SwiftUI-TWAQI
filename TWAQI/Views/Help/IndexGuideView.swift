//
//  IndexGuideView.swift
//  TWAQI
//
//  Created by kf on 21/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// What one index means, where it comes from and what to do about it, ending
/// with the colour bands the app actually scores it against.
struct IndexGuideView: View {
    var page: DefinitionPages

    private var type: AirIndexTypes { page.airIndexType }

    var body: some View {
        List {
            ForEach(Array(page.sections.enumerated()), id: \.offset) { _, section in
                Section(header: Text(section.header)) {
                    Text(section.body)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                }
            }

            Section(
                header: Text("Guide.section_bands"),
                footer: Text("Guide.bands_footer")
            ) {
                ForEach(Array((AirStatuses.bands[type] ?? []).enumerated()), id: \.offset) { index, band in
                    bandRow(band, isLast: index == (AirStatuses.bands[type]?.count ?? 0) - 1)
                }
            }

            Section(footer: Text("Guide.sources_footer")) {
                Link(destination: page.url) {
                    HStack {
                        Text("Guide.further_reading")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitle(page.title, displayMode: .inline)
        .onAppear {
            TrackingManager.logEvent(eventName: "open_definition_page", parameters: ["label": page.rawValue])
        }
    }

    private func bandRow(_ band: (range: Range<Double>, status: AirStatuses), isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(Color(band.status.getColor()))
                    .frame(width: 10, height: 10)

                Text(band.status.toString())

                Spacer()

                Text(verbatim: rangeText(band.range, isLast: isLast))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }

            // The AQI is what the health advice is keyed to.
            if type == .aqi {
                Text(band.status.getGeneralPublicGuidance())
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.leading, 18)
            }
        }
        .padding(.vertical, 2)
    }

    /// "15.5–35.4 µg/m3": bounds as a reader would say them, not the half-open
    /// ranges in code. The first band starts at zero; the last is open-ended.
    private func rangeText(_ range: Range<Double>, isLast: Bool) -> String {
        // PM2.5 and CO break at tenths (15.5, 4.5); the rest at whole numbers.
        let step = [.pm25, .co].contains(type) ? 0.1 : 1.0
        let decimals = step < 1 ? 1 : 0
        let unit = type.getUnit().isEmpty ? "" : " \(type.getUnit())"
        let lower = range.lowerBound <= step ? 0 : range.lowerBound
        let lowerText = String(format: "%.\(decimals)f", lower)

        if isLast {
            return "\(lowerText)+\(unit)"
        }
        let upperText = String(format: "%.\(decimals)f", range.upperBound - step)
        return "\(lowerText)–\(upperText)\(unit)"
    }
}

struct IndexGuideView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            IndexGuideView(page: .pm25)
        }
    }
}
