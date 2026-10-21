//
//  ReadingView.swift
//  TWAQIWatch
//
//  Created by kf on 20/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Charts
import SwiftUI

/// The station's reading: AQI first, then the pollutants behind it and the
/// past day of whichever index is selected.
struct ReadingView: View {
    @ObservedObject var model: WatchModel

    /// Drives the history chart. Local to this screen, as on the iOS station page.
    @State private var selected: AirIndexTypes = .aqi

    private static let pollutants: [AirIndexTypes] = [.pm25, .pm10, .o3, .co, .so2, .no2]

    /// Set when the station changes while the picker covers this screen, which
    /// can't be scrolled until it is back on screen.
    @State private var needsScrollToTop = false
    @State private var isVisible = false

    private static let topID = "top"

    var body: some View {
        ScrollViewReader { proxy in
            list
                // A new station starts at its headline reading, not wherever the
                // last one was scrolled to.
                .onChange(of: model.reading?.stationId) { _, _ in
                    if isVisible {
                        proxy.scrollTo(Self.topID, anchor: .top)
                    } else {
                        needsScrollToTop = true
                    }
                }
                .onAppear {
                    isVisible = true
                    guard needsScrollToTop else { return }
                    needsScrollToTop = false
                    proxy.scrollTo(Self.topID, anchor: .top)
                }
                .onDisappear { isVisible = false }
        }
    }

    private var list: some View {
        List {
            if let reading = model.reading {
                Section {
                    summary(reading)
                        .id(Self.topID)
                }

                Section("Watch.history") {
                    history
                }

                Section {
                    ForEach(Self.pollutants, id: \.self) { type in
                        row(type, reading: reading)
                    }
                }

                // The app is free; complications are Pro. Last, so it never
                // pushes a reading off screen.
                if !model.isPro {
                    Section {
                        NavigationLink {
                            PaywallView(model: model)
                        } label: {
                            Label("Watch.pro_complications_cta", systemImage: "watchface.applewatch.case")
                        }
                    }
                }
            } else if model.failed {
                failure
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(model.reading?.displayName ?? "")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    StationPickerView(model: model)
                } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel(Text("Watch.stations"))
            }
        }
        .refreshable { await model.refresh() }
    }

    private func summary(_ reading: WatchReading) -> some View {
        let status = reading.status()
        let tint = Color(status.getColor())

        return Button {
            selected = .aqi
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Gauge(value: min(reading.aqi, 500), in: 0...500) {
                        Text(verbatim: "AQI")
                    } currentValueLabel: {
                        Text(reading.formatted(.aqi))
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(tint)

                    VStack(alignment: .leading, spacing: 2) {
                        // The same faces as the phone, so a glance reads the
                        // mood before the words.
                        HStack(spacing: 4) {
                            if status.hasFaceImage {
                                Image(status.getImage())
                                    .resizable()
                                    .frame(width: 20, height: 20)
                            }

                            Text(status.toString())
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(tint)

                        if !reading.publishTime.isEmpty {
                            Text(reading.publishTime.asPublishTime)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        wind(reading.wind)
                            .font(.footnote)
                    }
                }

                if let source = sourceLabel {
                    source
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(selectionBackground(.aqi))
    }

    /// Says why this station, when it wasn't picked by hand.
    private var sourceLabel: Label<Text, Image>? {
        switch model.source {
        case .pinned:
            return nil
        case .closest:
            return Label("Watch.closest", systemImage: "location.fill")
        case .fallback:
            return Label("Watch.default_station", systemImage: "house.fill")
        }
    }

    @ViewBuilder
    private var history: some View {
        let points = Array(model.history.enumerated())

        if points.count < 2 {
            // A same-station refresh keeps the old bars; only an empty chart
            // waits on a spinner.
            Group {
                if model.isLoading || model.isLoadingHistory {
                    ProgressView()
                } else {
                    Text("Details.no_trend_data")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 70)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "\(selected.toString()) \(selected.getUnit())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Chart(points, id: \.offset) { index, point in
                    let value = point.getValue(airIndexType: selected)
                    BarMark(
                        x: .value("Hour", index),
                        y: .value(selected.toString(), value)
                    )
                    .foregroundStyle(
                        Color(AirStatuses.checkAirStatus(airIndexType: selected, value: value).getColor())
                    )
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                }
                .frame(height: 70)

                HStack {
                    Text(model.history.first?.publishTime.asPublishTime ?? "")
                    Spacer()
                    Text(model.history.last?.publishTime.asPublishTime ?? "")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func row(_ type: AirIndexTypes, reading: WatchReading) -> some View {
        Button {
            selected = type
        } label: {
            HStack {
                Circle()
                    .fill(Color(reading.status(type).getColor()))
                    .frame(width: 8, height: 8)

                Text(type.toString())

                Spacer()

                Text(reading.formatted(type))
                    .monospacedDigit()

                Text(type.getUnit())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .listRowBackground(selectionBackground(type))
    }

    /// Marks the row the chart is showing; `nil` keeps the default platter.
    private func selectionBackground(_ type: AirIndexTypes) -> AnyView? {
        guard selected == type else { return nil }
        return AnyView(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.22))
        )
    }

    /// Sits with the AQI: which way the air is moving is part of the headline,
    /// not a footnote below the pollutants.
    private func wind(_ wind: Wind) -> some View {
        HStack(spacing: 4) {
            if wind.isCalm {
                Text("Wind.calm")
            } else {
                // Drawn pointing south, so the meteorological bearing (where the
                // wind comes *from*) leaves it pointing downwind.
                Image(systemName: "arrow.down")
                    .fontWeight(.semibold)
                    .rotationEffect(wind.arrowRotation)

                Text(verbatim: "\(wind.compassPoint) \(wind.speed.format(f: ".1")) m/s")
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var failure: some View {
        VStack(spacing: 8) {
            Text("Watch.loading_failed")
                .multilineTextAlignment(.center)

            Button("Watch.retry") {
                Task { await model.refresh() }
            }
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    }
}
