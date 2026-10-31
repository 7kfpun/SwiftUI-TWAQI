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
///
/// The last frame seen is kept on disk (`StationCamFrameCache`) and shown at
/// once while the latest one loads, so the picture never drops back to a
/// spinner, and offline the station still has its last view.
struct StationCamView: View {
    var state: StationCamState

    /// MOENV cams are 1920×1080.
    fileprivate static let aspectRatio: CGFloat = 16 / 9
    fileprivate static let cornerRadius: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Details.live_cam")

            switch state {
            case .loading:
                CamFrame { CamPlaceholder() }

            case .available(let cam):
                StationCamFrameView(cam: cam)

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
}

/// Loads one cam's frame: the saved one first, then the latest.
final class StationCamFrameLoader: ObservableObject {
    /// The frame on screen, saved or fresh.
    @Published private(set) var image: UIImage?
    /// Capture time of `image` — not necessarily the manifest's, while an
    /// older saved frame is standing in.
    @Published private(set) var imageTime: String?
    @Published private(set) var isRefreshing = false
    /// The latest frame couldn't be loaded; `image`, if any, is an older one.
    @Published private(set) var refreshFailed = false

    private let cache: StationCamFrameCache
    private var cam: StationCam?

    init(cache: StationCamFrameCache = .shared) {
        self.cache = cache
    }

    /// Shows `cam`'s saved frame, then fetches its latest. Called on every
    /// appearance: the same cam loads again only if its last fetch failed.
    func load(_ cam: StationCam) {
        if cam == self.cam, isRefreshing || !refreshFailed { return }
        if cam.siteId != self.cam?.siteId {
            image = nil
            imageTime = nil
        }
        self.cam = cam
        isRefreshing = true
        refreshFailed = false

        cache.savedFrame(siteId: cam.siteId) { [weak self] saved in
            guard let self, self.cam == cam else { return }
            if self.image == nil, let saved {
                self.image = saved.image
                self.imageTime = saved.time
            }
            // The saved frame is the manifest's latest: nothing to fetch.
            if let saved, saved.time != nil, saved.time == cam.time {
                self.image = saved.image
                self.imageTime = saved.time
                self.isRefreshing = false
                return
            }

            self.cache.fetch(cam) { [weak self] fresh in
                guard let self, self.cam == cam else { return }
                self.isRefreshing = false
                if let fresh {
                    withAnimation(.easeOut(duration: 0.25)) {
                        self.image = fresh.image
                        self.imageTime = fresh.time
                    }
                } else {
                    self.refreshFailed = true
                }
            }
        }
    }
}

private struct StationCamFrameView: View {
    let cam: StationCam
    @StateObject private var loader = StationCamFrameLoader()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CamFrame {
                if let image = loader.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .id(loader.imageTime)
                        .transition(.opacity)
                        .overlay(alignment: .topTrailing) {
                            if loader.isRefreshing {
                                ProgressView()
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .padding(8)
                            }
                        }
                } else if loader.refreshFailed {
                    CamUnavailable()
                } else {
                    CamPlaceholder()
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Details.live_cam"))
            .accessibilityAddTraits(.isImage)

            caption

            if loader.refreshFailed, loader.image != nil {
                Label {
                    Text("Details.cam_showing_saved")
                } icon: {
                    Image(systemName: "wifi.slash")
                }
                .font(.caption)
                .foregroundColor(.orange)
            }
        }
        // Keyed by URL, which carries the capture time: a new frame in the
        // manifest loads again, the same one doesn't.
        .task(id: cam.imageURL) {
            loader.load(cam)
        }
    }

    /// "Captured 22:30 · 36 min. ago · Image: MOENV" — of the frame shown,
    /// which offline may be older than the manifest's.
    private var caption: some View {
        let time = loader.image != nil ? loader.imageTime : cam.time
        let date = time.flatMap { ISO8601DateFormatter().date(from: $0) }

        return HStack(spacing: 4) {
            Image(systemName: "camera")
            if let date {
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

/// A fixed 16:9 box, so the layout does not jump when the frame arrives.
private struct CamFrame<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(StationCamView.aspectRatio, contentMode: .fit)
            .overlay(content)
            .clipShape(RoundedRectangle(cornerRadius: StationCamView.cornerRadius, style: .continuous))
    }
}

private struct CamPlaceholder: View {
    var body: some View {
        ZStack {
            Image(systemName: "video")
                .font(.title2)
                .foregroundColor(Color(.tertiaryLabel))
            ProgressView()
                .offset(y: 32)
        }
    }
}

private struct CamUnavailable: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "video.slash")
                .font(.title2)
            Text("Details.cam_unavailable")
                .font(.footnote)
        }
        .foregroundColor(.secondary)
    }
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
