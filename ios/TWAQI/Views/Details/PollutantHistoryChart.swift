//
//  PollutantHistoryChart.swift
//  TWAQI
//
//  Created by kf on 21/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// A pollutant's hourly history as a line, coloured by AQI level band.
///
/// Drawn by hand: Swift Charts needs iOS 16 and the app supports 15. Each
/// stretch between two readings takes the band of the later one, so the line
/// turns orange where the air did. Hours with no reading are gaps: the line
/// breaks there, and a lone reading is a dot.
///
/// Drag across it to read the exact value and time; `selected` is the hour
/// under the finger, nil at rest.
struct PollutantHistoryChart: View {
    let series: PollutantHistorySeries
    let airIndexType: AirIndexTypes
    @Binding var selected: Int?

    private let height: CGFloat = 110
    private let lineWidth: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Array(series.runs.enumerated()), id: \.offset) { _, run in
                    runView(run, size: proxy.size)
                }
                cursor(size: proxy.size)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard proxy.size.width > 0 else { return }
                        selected = series.index(atFraction: Double(drag.location.x / proxy.size.width))
                    }
                    .onEnded { _ in selected = nil }
            )
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilitySummary))
        .accessibilityAdjustableAction { direction in
            step(direction)
        }
    }

    // MARK: - Drawing

    private func runView(_ run: [Int], size: CGSize) -> some View {
        ZStack {
            if run.count == 1, let index = run.first {
                Circle()
                    .fill(color(at: index))
                    .frame(width: lineWidth * 2, height: lineWidth * 2)
                    .position(point(index, size: size))
            } else {
                ForEach(Array(zip(run, run.dropFirst())), id: \.0) { from, to in
                    Path { path in
                        path.move(to: point(from, size: size))
                        path.addLine(to: point(to, size: size))
                    }
                    .stroke(color(at: to), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    @ViewBuilder
    private func cursor(size: CGSize) -> some View {
        if let index = selected, series.samples.indices.contains(index) {
            let x = xPosition(index, width: size.width)
            Path { path in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            if series.samples[index].value != nil {
                Circle()
                    .fill(color(at: index))
                    .overlay(Circle().stroke(Color(UIColor.systemBackground), lineWidth: 2))
                    .frame(width: 12, height: 12)
                    .position(point(index, size: size))
            }
        }
    }

    private func color(at index: Int) -> Color {
        guard let value = series.samples[index].value else { return .secondary }
        return Color(AirStatuses.checkAirStatus(airIndexType: airIndexType, value: value).getColor())
    }

    // MARK: - Geometry

    private func xPosition(_ index: Int, width: CGFloat) -> CGFloat {
        guard series.samples.count > 1 else { return width / 2 }
        return width * CGFloat(index) / CGFloat(series.samples.count - 1)
    }

    /// Scaled to the series' own range, padded a little, like the bar chart it
    /// replaced: a zero baseline flattens a 60–89 day into a straight line.
    /// The padding is a fraction of the range because CO spans hundredths of a ppm.
    private func point(_ index: Int, size: CGSize) -> CGPoint {
        let value = series.samples[index].value ?? 0
        let low = series.lowest?.value ?? 0
        let high = series.highest?.value ?? 0
        let range = high - low
        let pad = range > 0 ? range * 0.15 : max(high * 0.05, 0.001)
        let lower = max(0, low - pad)
        let upper = max(high + pad, lower + 0.001)
        let fraction = CGFloat(max(0, min(1, (value - lower) / (upper - lower))))
        let inset = lineWidth + 4
        let y = inset + (size.height - 2 * inset) * (1 - fraction)
        return CGPoint(x: xPosition(index, width: size.width), y: y)
    }

    // MARK: - VoiceOver

    /// Lowest, highest and latest, which is what the line says at a glance.
    private var accessibilitySummary: String {
        let span: String
        if series.isShorterThanRange {
            span = String(
                format: NSLocalizedString("Details.history_span_hours %d", bundle: .appLanguage, comment: ""),
                series.coveredHours
            )
        } else {
            let key = series.range == .day ? "Details.history_span_day" : "Details.history_span_week"
            span = NSLocalizedString(key, bundle: .appLanguage, comment: "")
        }
        return String(
            format: NSLocalizedString("Details.history_a11y %@ %@ %@ %@ %@", bundle: .appLanguage, comment: ""),
            airIndexType.toString(),
            span,
            reading(series.lowest),
            reading(series.highest),
            reading(series.latest)
        )
    }

    private func reading(_ sample: HistorySample?) -> String {
        guard let value = sample?.value else {
            return NSLocalizedString("Details.history_no_reading", bundle: .appLanguage, comment: "")
        }
        return "\(value.format(f: airIndexType.getFormat())) \(airIndexType.getUnit())"
    }

    /// Swipe up/down moves the cursor an hour; it starts on the latest hour.
    private func step(_ direction: AccessibilityAdjustmentDirection) {
        guard !series.samples.isEmpty else { return }
        let last = series.samples.count - 1
        let current = selected ?? last
        switch direction {
        case .increment: selected = min(last, current + 1)
        case .decrement: selected = max(0, current - 1)
        @unknown default: break
        }
    }
}

enum PollutantHistoryFormat {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .taipei
        return formatter
    }()

    /// A reading's hour in Taiwan time, e.g. "Nov 21, 14:00", in the app's
    /// language, never the device's zone.
    static func hour(_ date: Date) -> String {
        formatter.locale = .app
        formatter.setLocalizedDateFormatFromTemplate("MMMdHHmm")
        return formatter.string(from: date)
    }
}
