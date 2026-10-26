//
//  ShareCardView.swift
//  TWAQI
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// The image a station is shared as: one reading, legible at a glance in a
/// chat thread or a story, with no app chrome around it.
///
/// Laid out at a fixed 4:5 size and rendered off screen, so it must not depend
/// on anything from the live screen — no dynamic type, no dark mode, no
/// safe area. Everything it shows is passed in.
struct ShareCardView: View {
    static let size = CGSize(width: 360, height: 450)

    var title: String
    var locality: String?
    var aqi: Double
    var pollutant: Pollutant?
    var publishTime: String?

    /// Shown under the AQI; the rest of the grid is too much for a card.
    private static let pollutants: [AirIndexTypes] = [.pm25, .pm10, .o3]

    var body: some View {
        let status = AirStatuses.checkAirStatus(airIndexType: .aqi, value: aqi)
        let foreground = Color(status.getForegroundColor())
        let hasReading = aqi > 0

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: "Taiwan Air")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let publishTime = publishTime {
                    Text(publishTime.asPublishDateTime)
                        .font(.system(size: 12, weight: .light))
                }
            }
            .opacity(0.85)

            Spacer(minLength: 16)

            Text(title)
                .font(.system(size: 26, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            if let locality = locality {
                Text(locality)
                    .font(.system(size: 14, weight: .light))
                    .lineLimit(1)
                    .opacity(0.85)
                    .padding(.top, 2)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "AQI")
                        .font(.system(size: 13, weight: .medium))
                        .opacity(0.85)
                    Text(hasReading ? "\(Int(aqi))" : "—")
                        .font(.system(size: 96, weight: .thin))
                        .lineLimit(1)
                }

                Spacer()

                // The faces are black line art, which vanishes on the darker
                // bands; drawn as a template they take the text colour.
                if status.hasFaceImage {
                    Image(status.getImage())
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 88, height: 88)
                }
            }
            .padding(.top, 12)

            Text(status.toString())
                .font(.system(size: 15, weight: .semibold))
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
                .background(foreground.opacity(0.15))
                .cornerRadius(8)

            Spacer(minLength: 16)

            if let pollutant = pollutant {
                HStack(spacing: 0) {
                    ForEach(Self.pollutants, id: \.self) { type in
                        reading(type, value: pollutant.getValue(airIndexType: type))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.bottom, 14)
            }

            if hasReading {
                Text(status.getGeneralPublicGuidance())
                    .font(.system(size: 13, weight: .light))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundColor(foreground)
        .padding(24)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color(status.getColor()), Color(status.getColor()).opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .background(Color.black)
        )
        .environment(\.colorScheme, .light)
    }

    /// Zero means the station doesn't measure it, as on the pollutant grid.
    private func reading(_ type: AirIndexTypes, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(type.toString())
                .font(.system(size: 12, weight: .medium))
                .opacity(0.85)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value > 0 ? value.format(f: type.getFormat()) : "—")
                    .font(.system(size: 20, weight: .regular))
                if value > 0 {
                    Text(type.getUnit())
                        .font(.system(size: 10, weight: .light))
                        .opacity(0.85)
                }
            }
        }
    }
}

struct ShareCardView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ShareCardView(
                title: "Keelung",
                locality: "Xinyi District, Keelung City",
                aqi: 54,
                pollutant: nil,
                publishTime: "2026-08-07T22:00:00"
            )

            ShareCardView(
                title: "臺灣大道",
                locality: nil,
                aqi: 162,
                pollutant: nil,
                publishTime: "2026-08-07T22:00:00"
            )
        }
        .previewLayout(.sizeThatFits)
    }
}
