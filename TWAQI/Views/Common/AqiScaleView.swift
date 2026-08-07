//
//  AqiScaleView.swift
//  TWAQI
//
//  Created by kf on 8/8/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// The AQI scale with a marker showing where this reading falls.
///
/// Replaces the old six-segment legend, which spelled out every band name at
/// full width — four of the six labels wrapped to two lines, it took a third of
/// a screen, and it said nothing about the station you were looking at.
struct AqiScaleView: View {
    var aqi: Double

    /// Upper bound of each band. The bar's segments are sized in proportion to
    /// these, so the marker's horizontal position is honest rather than
    /// six equal blocks with a marker placed by band index.
    private static let bands: [(upper: Double, status: AirStatuses)] = [
        (50, .good),
        (100, .moderate),
        (150, .unhealthyforsensitivegroup),
        (200, .unhealthy),
        (300, .veryunhealthy),
        (500, .hazardous),
    ]

    private static let scaleMax: Double = 500

    var body: some View {
        let status = AirStatuses.checkAirStatus(airIndexType: .aqi, value: aqi)
        let fraction = min(max(aqi / Self.scaleMax, 0), 1)

        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                let width = geometry.size.width

                ZStack(alignment: .topLeading) {
                    HStack(spacing: 2) {
                        ForEach(Array(Self.bands.enumerated()), id: \.offset) { index, band in
                            let lower = index == 0 ? 0 : Self.bands[index - 1].upper
                            Capsule()
                                .fill(Color(band.status.getColor()))
                                .frame(width: max(0, width * CGFloat((band.upper - lower) / Self.scaleMax) - 2))
                        }
                    }
                    .frame(height: 6)

                    if aqi > 0 {
                        Circle()
                            .strokeBorder(Color(status.getColor()), lineWidth: 3)
                            .background(Circle().fill(Color(UIColor.systemBackground)))
                            .frame(width: 14, height: 14)
                            .offset(x: width * CGFloat(fraction) - 7, y: -4)
                    }
                }
            }
            .frame(height: 14)

            HStack {
                Text(verbatim: "0")
                Spacer()
                Text(verbatim: "500")
            }
            .font(.caption2.weight(.light))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }
}

struct AqiScaleView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AqiScaleView(aqi: 42)
            AqiScaleView(aqi: 96)
            AqiScaleView(aqi: 175)
            AqiScaleView(aqi: 0)
        }
        .previewLayout(.fixed(width: 390, height: 70))
    }
}
