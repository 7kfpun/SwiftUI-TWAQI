//
//  ShareCardView.swift
//  TWAQI
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// Where the card is going decides its shape (FOX-73). Every shape is 360 pt
/// wide and rendered at 3x, so 1080 px wide.
enum ShareCardShape: String, CaseIterable, Identifiable {
    /// 4:5, a feed post (Instagram, Threads, Facebook): 1080 × 1350.
    case feed = "4x5"
    /// 9:16, a story (Instagram Stories, LINE VOOM): 1080 × 1920.
    case story = "9x16"
    /// 1:1, a LINE chat: 1080 × 1080.
    case square = "1x1"

    /// The last shape chosen in the preview, in the app's own defaults.
    static let defaultsKey = "shareCardShape"

    /// Pixels per point when rendered.
    static let renderScale: CGFloat = 3

    static let width: CGFloat = 360

    var id: String { rawValue }

    /// The card's layout size in points.
    var size: CGSize {
        switch self {
        case .feed: return CGSize(width: Self.width, height: 450)
        case .story: return CGSize(width: Self.width, height: 640)
        case .square: return CGSize(width: Self.width, height: 360)
        }
    }

    /// The rendered image's size in pixels.
    var pixelSize: CGSize {
        CGSize(width: size.width * Self.renderScale, height: size.height * Self.renderScale)
    }

    /// The preview's shape picker.
    var label: LocalizedStringKey {
        switch self {
        case .feed: return "Share.shape_feed"
        case .story: return "Share.shape_story"
        case .square: return "Share.shape_square"
        }
    }
}

/// The image a station is shared as: one reading, legible at a glance in a
/// chat thread or a story, with no app chrome around it.
///
/// Laid out at a fixed size per shape and rendered off screen, so it must not
/// depend on anything from the live screen — no dynamic type, no dark mode, no
/// safe area. Everything it shows is passed in.
struct ShareCardView: View {
    var title: String
    var locality: String?
    var aqi: Double
    var pollutant: Pollutant?
    var publishTime: String?
    var shape: ShareCardShape = .feed

    /// Shown under the AQI; the rest of the grid is too much for a card.
    private static let pollutants: [AirIndexTypes] = [.pm25, .pm10, .o3]

    /// What each shape has room for. The square drops the locality and the
    /// guidance rather than squeezing them; the story has room to spare.
    private struct Metrics {
        let padding: CGFloat
        let titleSize: CGFloat
        let titleLines: Int
        let showsLocality: Bool
        let numberSize: CGFloat
        let faceSize: CGFloat
        let readingSize: CGFloat
        let guidanceLines: Int
        let iconSize: CGFloat
    }

    private var metrics: Metrics {
        switch shape {
        case .feed:
            return Metrics(
                padding: 24, titleSize: 26, titleLines: 2, showsLocality: true,
                numberSize: 84, faceSize: 76, readingSize: 20, guidanceLines: 2, iconSize: 28
            )
        case .story:
            return Metrics(
                padding: 28, titleSize: 30, titleLines: 3, showsLocality: true,
                numberSize: 112, faceSize: 100, readingSize: 22, guidanceLines: 4, iconSize: 36
            )
        case .square:
            return Metrics(
                padding: 20, titleSize: 22, titleLines: 2, showsLocality: false,
                numberSize: 64, faceSize: 60, readingSize: 18, guidanceLines: 0, iconSize: 24
            )
        }
    }

    var body: some View {
        let status = AirStatuses.checkAirStatus(airIndexType: .aqi, value: aqi)
        let foreground = Color(status.getForegroundColor())
        let hasReading = aqi > 0
        let metrics = self.metrics

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

            Spacer(minLength: 12)

            Text(title)
                .font(.system(size: metrics.titleSize, weight: .semibold))
                .lineLimit(metrics.titleLines)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)

            if metrics.showsLocality, let locality = locality {
                Text(locality)
                    .font(.system(size: 14, weight: .light))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .opacity(0.85)
                    .padding(.top, 2)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "AQI")
                        .font(.system(size: 13, weight: .medium))
                        .opacity(0.85)
                    Text(hasReading ? "\(Int(aqi))" : "—")
                        .font(.system(size: metrics.numberSize, weight: .thin))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }

                Spacer(minLength: 0)

                // The faces are black line art, which vanishes on the darker
                // bands; drawn as a template they take the text colour.
                if status.hasFaceImage {
                    Image(status.getImage())
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: metrics.faceSize, height: metrics.faceSize)
                }
            }
            .padding(.top, 8)

            Text(status.toString())
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
                .background(foreground.opacity(0.15))
                .cornerRadius(8)

            Spacer(minLength: 12)

            if let pollutant = pollutant {
                HStack(spacing: 0) {
                    ForEach(Self.pollutants, id: \.self) { type in
                        reading(type, value: pollutant.getValue(airIndexType: type), size: metrics.readingSize)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.bottom, 12)
            }

            if hasReading, metrics.guidanceLines > 0 {
                Text(status.getGeneralPublicGuidance())
                    .font(.system(size: 13, weight: .light))
                    .lineLimit(metrics.guidanceLines)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
            }

            brand(iconSize: metrics.iconSize, foreground: foreground)
        }
        .foregroundColor(foreground)
        .padding(metrics.padding)
        .frame(width: shape.size.width, height: shape.size.height, alignment: .topLeading)
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

    /// The app icon and where to get it, so the picture still points at the
    /// app when a chat or a story drops the text sent with it.
    private func brand(iconSize: CGFloat, foreground: Color) -> some View {
        HStack(spacing: 8) {
            Image("ShareCardAppIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.225, style: .continuous))
            Text("Share.download")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(foreground.opacity(0.25))
                .frame(height: 1)
        }
    }

    /// Zero means the station doesn't measure it, as on the pollutant grid.
    private func reading(_ type: AirIndexTypes, value: Double, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(type.toString())
                .font(.system(size: 12, weight: .medium))
                .opacity(0.85)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value > 0 ? value.format(f: type.getFormat()) : "—")
                    .font(.system(size: size, weight: .regular))
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
            ForEach(ShareCardShape.allCases) { shape in
                ShareCardView(
                    title: "Keelung",
                    locality: "Xinyi District, Keelung City",
                    aqi: 54,
                    pollutant: nil,
                    publishTime: "2026-08-07T22:00:00",
                    shape: shape
                )
            }

            ShareCardView(
                title: "臺灣大道",
                locality: nil,
                aqi: 162,
                pollutant: nil,
                publishTime: "2026-08-07T22:00:00"
            )
            .environment(\.locale, Locale(identifier: "zh-Hant"))
        }
        .previewLayout(.sizeThatFits)
    }
}
