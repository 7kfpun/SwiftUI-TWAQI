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
///
/// A scrubber under the frame steps back through the past 24 clock hours, one
/// frame each (`StationCamHistoryLoader`), loading only the hour on screen and
/// its neighbours.
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

/// The scrubber's side of the cam: the past 24 clock hours, one frame each.
///
/// Lazy by design. While the finger moves, only the hour under it is shown —
/// from memory or a downsampled decode of its saved file, never the network.
/// When the scrubber comes to rest, that hour and two either side load (disk,
/// then network), the rest are forgotten, and the resting hour's full-res
/// frame replaces its thumbnail. Nothing fetches the whole day.
///
/// While an hour loads, whatever was on screen stays up as a stand-in, so the
/// frame never drops back to a spinner.
final class StationCamHistoryLoader: ObservableObject {
    enum SlotState: Equatable {
        case loading, loaded, missing, failed
    }

    /// The 24 hours on offer, oldest first.
    @Published private(set) var slots: [StationCamHour] = []
    @Published private(set) var states: [StationCamHour: SlotState] = [:]
    /// The hour picked on the scrubber; nil is live.
    @Published private(set) var selected: StationCamHour?
    /// What the frame shows for `selected`: its full-res frame once settled,
    /// its thumbnail while scrubbing, or the last frame shown, standing in
    /// while it loads.
    @Published private(set) var image: UIImage?
    /// `image` is an earlier frame standing in while `selected` loads.
    @Published private(set) var isStandIn = false

    /// A 404'd hour is asked for again after this long: the current hour's
    /// frame may simply not have been filed yet.
    static let missingRetry: TimeInterval = 5 * 60

    private let cache: StationCamHistoryCache
    private let now: () -> Date
    /// Thumbnails of `window`, plus the hour under the finger.
    private var thumbnails: [StationCamHour: UIImage] = [:]
    private var full: (hour: StationCamHour, image: UIImage)?
    private var settled: StationCamHour?
    /// The settled hour and its neighbours: the only hours fetched, and the
    /// only thumbnails kept besides the one under the finger.
    private var window: Set<StationCamHour> = []
    private var missingAt: [StationCamHour: Date] = [:]

    init(cache: StationCamHistoryCache = .shared, now: @escaping () -> Date = Date.init) {
        self.cache = cache
        self.now = now
    }

    var selectedState: SlotState? {
        selected.flatMap { states[$0] }
    }

    /// The 24 hours up to `anchor` (the live frame's capture time). A new
    /// anchor slides the window; hours still in it keep what they loaded.
    func configure(siteId: String, anchor: Date) {
        let slots = StationCamHour.slots(siteId: siteId, anchor: anchor)
        guard slots != self.slots else { return }

        if slots.first?.siteId != self.slots.first?.siteId {
            states = [:]
            thumbnails = [:]
            missingAt = [:]
            full = nil
            settled = nil
            window = []
            selected = nil
            image = nil
            isStandIn = false
        } else {
            let kept = Set(slots)
            states = states.filter { kept.contains($0.key) }
            thumbnails = thumbnails.filter { kept.contains($0.key) }
            missingAt = missingAt.filter { kept.contains($0.key) }
            if let full, !kept.contains(full.hour) { self.full = nil }
            if let selected, !kept.contains(selected) { showLive() }
        }
        self.slots = slots
    }

    /// Back to the live frame.
    func showLive() {
        selected = nil
        settled = nil
    }

    /// Scrubbing over `index`: shows it if it's in memory or on disk. No
    /// network. `standIn` is shown meanwhile if nothing is up yet.
    func preview(_ index: Int, standIn: UIImage?) {
        guard slots.indices.contains(index) else { return }
        let hour = slots[index]
        if selected == nil, image == nil || standIn != nil {
            image = standIn
        }
        selected = hour
        if settled != hour { settled = nil }
        show(hour)

        guard thumbnails[hour] == nil, states[hour] != .missing else { return }
        cache.savedThumbnail(hour) { [weak self] thumbnail in
            guard let self, let thumbnail, self.selected == hour, self.slots.contains(hour) else { return }
            // One scrubbing thumbnail at a time, on top of the settled window.
            self.thumbnails = self.thumbnails.filter { self.window.contains($0.key) }
            self.thumbnails[hour] = thumbnail
            self.states[hour] = .loaded
            self.show(hour)
        }
    }

    /// The scrubber came to rest on `index`: it and its neighbours load, and
    /// its full-res frame replaces the thumbnail.
    func settle(_ index: Int) {
        guard slots.indices.contains(index) else { return }
        let hour = slots[index]
        selected = hour
        settled = hour

        let nearby = StationCamHour.window(around: index).map { slots[$0] }
        window = Set(nearby)
        thumbnails = thumbnails.filter { window.contains($0.key) }
        if let full, full.hour != hour { self.full = nil }

        show(hour)
        nearby.forEach(load)
    }

    // MARK: Private

    private func load(_ hour: StationCamHour) {
        switch states[hour] {
        case .loading:
            return
        case .missing:
            if let at = missingAt[hour], now().timeIntervalSince(at) < Self.missingRetry { return }
        default:
            break
        }
        if thumbnails[hour] != nil {
            loadFull(hour)
            return
        }

        states[hour] = .loading
        if selected == hour { show(hour) }
        cache.load(hour) { [weak self] result in
            guard let self, self.slots.contains(hour) else { return }
            switch result {
            case .thumbnail(let thumbnail):
                self.states[hour] = .loaded
                self.missingAt[hour] = nil
                // Kept only if still near where the scrubber rests.
                if self.window.contains(hour) || self.selected == hour {
                    self.thumbnails[hour] = thumbnail
                }
                self.loadFull(hour)
            case .missing:
                self.states[hour] = .missing
                self.missingAt[hour] = self.now()
            case .failed:
                self.states[hour] = .failed
            }
            if self.selected == hour { self.show(hour) }
        }
    }

    /// Full-res decode, for the settled hour only.
    private func loadFull(_ hour: StationCamHour) {
        guard settled == hour, full?.hour != hour else { return }
        cache.savedFullImage(hour) { [weak self] image in
            guard let self, let image, self.settled == hour else { return }
            self.full = (hour, image)
            self.show(hour)
        }
    }

    private func show(_ hour: StationCamHour) {
        guard selected == hour else { return }
        if let full, full.hour == hour {
            image = full.image
            isStandIn = false
        } else if let thumbnail = thumbnails[hour] {
            image = thumbnail
            isStandIn = false
        } else {
            // Loading, not asked for yet, or nothing to show (the view puts a
            // placeholder over a missing hour): keep the last frame for later.
            isStandIn = image != nil
        }
    }
}

private struct StationCamFrameView: View {
    let cam: StationCam
    @StateObject private var loader = StationCamFrameLoader()
    @StateObject private var history = StationCamHistoryLoader()

    /// Scrubber position: 0..<24 are the hourly slots, oldest first; 24 is live.
    @State private var position = Double(StationCamHour.count)

    /// How long the scrubber must rest before its hour loads in full.
    private static let settleDelay: UInt64 = 300_000_000

    /// The hourly slot picked, or nil for live.
    private var selectedIndex: Int? {
        let index = Int(position.rounded())
        return index < StationCamHour.count ? index : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CamFrame {
                if selectedIndex == nil {
                    liveFrame
                } else {
                    historyFrame
                }
            }
            .overlay(alignment: .topLeading) {
                if let hour = history.selected, selectedIndex != nil {
                    Text(Self.timeFormatter.string(from: hour.hour))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(8)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Details.live_cam"))
            .accessibilityAddTraits(.isImage)

            caption

            scrubber

            if selectedIndex == nil, loader.refreshFailed, loader.image != nil {
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
            history.configure(siteId: cam.siteId, anchor: cam.capturedAt ?? Date())
            // A new anchor slides the hours under a resting scrubber.
            if let index = selectedIndex {
                history.settle(index)
            }
        }
        .onChange(of: selectedIndex) { index in
            if let index {
                history.preview(index, standIn: loader.image)
            } else {
                history.showLive()
            }
        }
        // Settles once the scrubber has rested; each move cancels the last.
        .task(id: selectedIndex) {
            guard let index = selectedIndex else { return }
            try? await Task.sleep(nanoseconds: Self.settleDelay)
            guard !Task.isCancelled else { return }
            history.settle(index)
        }
    }

    @ViewBuilder
    private var liveFrame: some View {
        if let image = loader.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .id(loader.imageTime)
                .transition(.opacity)
                .overlay(alignment: .topTrailing) {
                    if loader.isRefreshing {
                        RefreshBadge()
                    }
                }
        } else if loader.refreshFailed {
            CamUnavailable()
        } else {
            CamPlaceholder()
        }
    }

    /// The picked hour. While it loads the last frame stays up, dimmed, rather
    /// than a spinner; an hour with no frame says so, and the rest still work.
    @ViewBuilder
    private var historyFrame: some View {
        switch history.selectedState {
        case .missing:
            CamHourMissing()
        case .failed:
            CamUnavailable()
        default:
            if let image = history.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .opacity(history.isStandIn ? 0.45 : 1)
                    .overlay(alignment: .topTrailing) {
                        if history.isStandIn || history.selectedState == .loading {
                            RefreshBadge()
                        }
                    }
            } else {
                CamPlaceholder()
            }
        }
    }

    /// Past 24 hours on the left, live on the right; whole hours only.
    private var scrubber: some View {
        VStack(spacing: 0) {
            Slider(value: $position, in: 0...Double(StationCamHour.count), step: 1)
                .accessibilityLabel(Text("Details.cam_timeline"))
                .accessibilityValue(Text(accessibilityValue))
            HStack {
                Text("Timeline.title")
                Spacer()
                Button {
                    position = Double(StationCamHour.count)
                } label: {
                    Text("Details.cam_live")
                        .fontWeight(selectedIndex == nil ? .semibold : .regular)
                }
                .buttonStyle(.borderless)
                .disabled(selectedIndex == nil)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
    }

    private var accessibilityValue: String {
        guard let hour = history.selected, selectedIndex != nil else { return "Details.cam_live".localized }
        return Self.timeFormatter.string(from: hour.hour)
            + " " + Self.relativeFormatter.localizedString(for: hour.hour, relativeTo: Date())
    }

    /// "Captured 22:30 · 36 min. ago · Image: MOENV" — of the live frame shown,
    /// which offline may be older than the manifest's, or of the picked hour.
    private var caption: some View {
        let date: Date?
        if let hour = history.selected, selectedIndex != nil {
            date = hour.hour
        } else {
            let time = loader.image != nil ? loader.imageTime : cam.time
            date = time.flatMap { ISO8601DateFormatter().date(from: $0) }
        }

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
        formatter.timeZone = StationCamHour.timeZone
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

/// The small spinner in the frame's corner: a newer frame is on its way.
private struct RefreshBadge: View {
    var body: some View {
        ProgressView()
            .padding(6)
            .background(.ultraThinMaterial, in: Circle())
            .padding(8)
    }
}

/// An hour the cam has no frame for. Only that slot; the others still load.
private struct CamHourMissing: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.title2)
            Text("Details.cam_hour_missing")
                .font(.footnote)
        }
        .foregroundColor(.secondary)
    }
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
