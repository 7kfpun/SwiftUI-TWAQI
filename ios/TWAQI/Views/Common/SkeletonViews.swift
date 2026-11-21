//
//  SkeletonViews.swift
//  TWAQI
//
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// Placeholder shapes for content that is still loading (TWAQ-19): the layout
/// of what will arrive, so the screen doesn't jump and never reads as empty.
/// They pulse gently, and hold still under Reduce Motion.
private struct SkeletonPulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(dimmed ? 0.45 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Loading.label"))
    }
}

extension View {
    /// Draws the view as a grey placeholder of its own shape.
    func skeleton() -> some View {
        redacted(reason: .placeholder).modifier(SkeletonPulse())
    }
}

extension View {
    /// Pull-to-refresh on a `ScrollView`, which only has it from iOS 16. On
    /// iOS 15 the page's Retry button is the way to try again.
    @ViewBuilder
    func pullToRefresh(_ action: @escaping @Sendable () async -> Void) -> some View {
        if #available(iOS 16.0, *) {
            refreshable(action: action)
        } else {
            self
        }
    }
}

/// A favourites row while its reading loads.
struct SkeletonStationRow: View {
    var body: some View {
        StationRow(
            title: "Placeholder station",
            subtitle: "Placeholder locality, city",
            reading: .init(aqi: 50, publishTime: "2026-01-01T00:00:00", pollutants: [
                .init(type: .pm25, value: 10), .init(type: .pm10, value: 20), .init(type: .o3, value: 30),
            ])
        )
        .skeleton()
    }
}

/// The favourites list while the first load is on the wire.
struct SkeletonStationList: View {
    var rows = 4

    var body: some View {
        List {
            Section {
                ForEach(0..<rows, id: \.self) { _ in
                    SkeletonStationRow()
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .disabled(true)
    }
}

/// The station screen's header while neither a saved nor a live reading is in.
struct SkeletonStationHeader: View {
    var body: some View {
        StationHeaderView(
            title: "Placeholder station",
            locality: "Placeholder locality, city",
            area: "Area",
            stationType: .unknown,
            aqi: 50,
            publishTime: "2026-01-01T00:00:00"
        )
        .skeleton()
    }
}
