//
//  StationHeaderView.swift
//  TWAQI
//
//  Created by kf on 8/8/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// Top of the station screen: identity, current AQI, and how fresh it is.
struct StationHeaderView: View {
    var title: String
    var locality: String?
    var area: String?
    var stationType: StationTypes
    var aqi: Double
    var publishTime: String?

    var body: some View {
        let airStatus = AirStatuses.checkAirStatus(airIndexType: .aqi, value: aqi)
        let hasReading = aqi > 0

        return VStack(alignment: .leading, spacing: 12) {
            // Identity
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)

                if let locality = locality {
                    Text(locality)
                        .font(.subheadline)
                        .fontWeight(.light)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 6) {
                    if stationType.isDisplayable {
                        Label {
                            Text(stationType.toString())
                        } icon: {
                            Image(systemName: stationType.getIcon())
                        }
                        .font(.caption.weight(.light))
                        .foregroundColor(.secondary)
                    }

                    if let area = area {
                        Text(area)
                            .font(.caption)
                            .fontWeight(.light)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 2)
            }

            // Current reading
            HStack(alignment: .center, spacing: 16) {
                if airStatus.hasFaceImage {
                    Image(airStatus.getImage())
                        .resizable()
                        .frame(width: 64, height: 64)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("AQI")
                            .font(.caption)
                            .fontWeight(.light)
                            .foregroundColor(.secondary)

                        Text(hasReading ? "\(Int(aqi))" : "—")
                            .font(.system(size: 40, weight: .thin))
                    }

                    Text(airStatus.toString())
                        .font(.footnote)
                        .foregroundColor(Color(airStatus.getForegroundColor()))
                        .padding(.vertical, 3)
                        .padding(.horizontal, 10)
                        .background(Color(airStatus.getColor()))
                        .cornerRadius(6)
                }

                Spacer()
            }

            if let publishTime = publishTime {
                LastUpdatedView(publishTime: publishTime)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

/// "Last updated 22:00 · 2h ago" — shared by the map card and station screen.
struct LastUpdatedView: View {
    var publishTime: String
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
            if compact {
                Text(publishTime.asPublishTime)
            } else {
                Text("Details.last_updated")
                Text(publishTime.asPublishDateTime)
            }

            let age = publishTime.asRelativeAge
            if !age.isEmpty {
                Text("· \(age)")
                    .foregroundColor(.secondary)
            }
        }
        .font(.caption.weight(.light))
        .foregroundColor(.secondary)
    }
}

struct StationHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            StationHeaderView(
                title: "Keelung",
                locality: "Xinyi District, Keelung City",
                area: "North",
                stationType: .general,
                aqi: 54,
                publishTime: "2026-08-07T22:00:00"
            )

            StationHeaderView(
                title: "臺灣大道",
                locality: nil,
                area: nil,
                stationType: .unknown,
                aqi: 0,
                publishTime: "2026-08-07T22:00:00"
            )
        }
        .previewLayout(.sizeThatFits)
    }
}
