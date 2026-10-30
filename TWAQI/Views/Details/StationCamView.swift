//
//  StationCamView.swift
//  TWAQI
//
//  Created by kf on 30/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// The view from the station: MOENV's latest webcam frame.
///
/// Sits under the AQI so the number and the sky it describes are read
/// together. Stations without a cam get one quiet line, not an empty frame.
struct StationCamView: View {
    var state: StationCamState

    /// MOENV cams are 1920×1080.
    private static let aspectRatio: CGFloat = 16 / 9
    private static let cornerRadius: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Details.live_cam")

            switch state {
            case .loading:
                frame { placeholder }

            case .available(let cam):
                frame {
                    AsyncImage(url: cam.imageURL, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .transition(.opacity)
                        case .failure:
                            unavailable
                        default:
                            placeholder
                        }
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(Text("Details.live_cam"))
                .accessibilityAddTraits(.isImage)

                caption(for: cam)

            case .missing:
                Label {
                    Text("Details.no_cam")
                } icon: {
                    Image(systemName: "video.slash")
                }
                .font(.footnote)
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }

    /// A fixed 16:9 box, so the layout does not jump when the frame arrives.
    private func frame<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Color(.secondarySystemBackground)
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .overlay(content())
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            Image(systemName: "video")
                .font(.title2)
                .foregroundColor(Color(.tertiaryLabel))
            ProgressView()
                .offset(y: 32)
        }
    }

    private var unavailable: some View {
        VStack(spacing: 6) {
            Image(systemName: "video.slash")
                .font(.title2)
            Text("Details.cam_unavailable")
                .font(.footnote)
        }
        .foregroundColor(.secondary)
    }

    /// "Captured 22:30 · 36 min. ago · Image: MOENV"
    private func caption(for cam: StationCam) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "camera")
            if let date = cam.capturedAt {
                Text("Details.cam_captured \(Self.timeFormatter.string(from: date))")
                Text("· \(Self.relativeFormatter.localizedString(for: date, relativeTo: Date()))")
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            Text("Details.cam_source")
        }
        .font(.caption.weight(.light))
        .foregroundColor(.secondary)
        .lineLimit(1)
    }

    /// Taiwan time, like every other timestamp on this screen.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei")
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

struct StationCamView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 24) {
            StationCamView(state: .available(StationCam(
                siteId: "001",
                name: "基隆",
                lat: 25.129167,
                lon: 121.760056,
                time: "2026-10-30T22:30:00+08:00"
            )))
            StationCamView(state: .loading)
            StationCamView(state: .missing)
        }
        .previewLayout(.sizeThatFits)
    }
}
