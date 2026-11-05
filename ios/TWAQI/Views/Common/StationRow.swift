//
//  StationRow.swift
//  TWAQI
//
//  Created by kf on 8/8/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// One station in a list: identity on the left, an optional current reading on
/// the right. Shared by the favourites and search screens so both stay in step.
struct StationRow: View {
    var title: String
    var subtitle: String?
    /// Omitted on the search screen, where no reading has been fetched.
    var reading: Reading?
    /// A bell beside the name: the station has an AQI alert on.
    var alertsOn = false

    struct Reading {
        var aqi: Double
        var publishTime: String?
        /// A few pollutants, one line under the locality. Empty leaves the
        /// row as just the AQI.
        var pollutants: [PollutantValue] = []
    }

    struct PollutantValue: Hashable {
        var type: AirIndexTypes
        var value: Double
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.body)

                    if alertsOn {
                        Image(systemName: "bell.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .accessibilityLabel(Text("Favourites.alerts_on"))
                    }
                }

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .fontWeight(.light)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if let pollutants = reading?.pollutants, !pollutants.isEmpty {
                    pollutantLine(pollutants)
                        .padding(.top, 2)
                }

                if let publishTime = reading?.publishTime {
                    LastUpdatedView(publishTime: publishTime, compact: true)
                }
            }

            Spacer(minLength: 8)

            if let reading = reading {
                readingBadge(aqi: reading.aqi)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// "PM2.5 18  PM10 32  O3 41.2" as one line of text, each value in its
    /// band colour like the station screen's grid. One `Text` so it shrinks
    /// as a whole at large type sizes rather than wrapping mid-pair. Zero is
    /// "—": several stations report 0.0 for what they don't measure.
    private func pollutantLine(_ pollutants: [PollutantValue]) -> some View {
        let line = pollutants.enumerated().reduce(Text(verbatim: "")) { text, item in
            let (index, pollutant) = item
            let hasReading = pollutant.value > 0
            let status = AirStatuses.checkAirStatus(airIndexType: pollutant.type, value: pollutant.value)
            let value = Text(hasReading ? pollutant.value.format(f: pollutant.type.getFormat()) : "—")
                .fontWeight(.medium)
                .foregroundColor(hasReading ? Color(status.getColor()) : .secondary)
            return text
                + Text(verbatim: index == 0 ? "" : "   ")
                + Text(verbatim: "\(pollutant.type.toString()) ").foregroundColor(.secondary)
                + value
        }

        return line
            .font(.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func readingBadge(aqi: Double) -> some View {
        let airStatus = AirStatuses.checkAirStatus(airIndexType: .aqi, value: aqi)

        return VStack(spacing: 4) {
            LabelView(airIndexTypes: .aqi, value: aqi)

            Text(airStatus.toString())
                .font(.system(size: 10))
                .fontWeight(.light)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: 84)
    }
}

/// Centred placeholder for an empty or still-loading list.
struct EmptyStateView: View {
    var icon: String
    var message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .thin))
                .foregroundColor(.secondary)

            Text(message)
                .font(.callout)
                .fontWeight(.light)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 64)
    }
}

/// One line saying the readings below are the last good ones saved, because
/// the latest request failed. Each reading already shows its own time.
struct OfflineNotice: View {
    var body: some View {
        Label {
            Text("Offline.showing_saved_readings")
        } icon: {
            Image(systemName: "wifi.slash")
        }
        .font(.footnote)
        .foregroundColor(.orange)
        .accessibilityElement(children: .combine)
    }
}

/// Nothing could be loaded and nothing was saved to show instead.
struct OfflineEmptyStateView: View {
    var retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            EmptyStateView(icon: "wifi.slash", message: "Offline.nothing_saved")
            Button(action: retry) {
                Text("Offline.retry")
            }
            .buttonStyle(.bordered)
        }
    }
}

/// Navigation for the station lists and Help. In a wide window — iPad, an
/// unfolded iPhone Duo, a large split-screen window — the list and the chosen
/// page sit side by side; in a narrow one it is the usual push stack. Follows
/// the window as it resizes, folds and unfolds.
struct AdaptiveNavigation<Sidebar: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.foldLineX) private var foldLineX

    private let sidebar: Sidebar
    private let placeholderIcon: String
    private let placeholderMessage: LocalizedStringKey

    /// The placeholder fills the second column until something is chosen.
    init(
        placeholderIcon: String = "aqi.medium",
        placeholderMessage: LocalizedStringKey = "Details.select_a_station",
        @ViewBuilder sidebar: () -> Sidebar
    ) {
        self.sidebar = sidebar()
        self.placeholderIcon = placeholderIcon
        self.placeholderMessage = placeholderMessage
    }

    var body: some View {
        if horizontalSizeClass == .regular {
            if #available(iOS 16.0, *) {
                if foldLineX == nil {
                    // iPad and the like: laid out exactly as without a fold.
                    splitView(sidebarWidth: nil)
                } else {
                    GeometryReader { geometry in
                        splitView(sidebarWidth: FoldLine.leadingWidth(
                            foldX: foldLineX,
                            in: Self.fullFrame(of: geometry)
                        ))
                    }
                }
            } else {
                NavigationView {
                    sidebar
                    noSelection
                }
                .navigationViewStyle(DoubleColumnNavigationViewStyle())
            }
        } else {
            NavigationView {
                sidebar
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
    }

    /// On an unfolded iPhone Duo the list ends on the fold, so the list and
    /// the page each get a half of the display to themselves. Elsewhere the
    /// system's own sidebar width.
    @available(iOS 16.0, *)
    @ViewBuilder
    private func splitView(sidebarWidth: CGFloat?) -> some View {
        if let sidebarWidth = sidebarWidth {
            splitView { sidebarColumn.navigationSplitViewColumnWidth(sidebarWidth) }
        } else {
            splitView { sidebarColumn }
        }
    }

    @available(iOS 16.0, *)
    private func splitView<Column: View>(@ViewBuilder sidebar: () -> Column) -> some View {
        // Both columns always: a hideable list would leave an iPad in
        // portrait opening on an empty "select a station" page.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar()
        } detail: {
            noSelection
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var sidebarColumn: some View {
        if #available(iOS 17.0, *) {
            sidebar.toolbar(removing: .sidebarToggle)
        } else {
            sidebar
        }
    }

    private var noSelection: some View {
        EmptyStateView(icon: placeholderIcon, message: placeholderMessage)
    }

    /// The split view's frame in the window, safe areas included: its columns
    /// are measured from the window's edge, not from inside the safe area.
    private static func fullFrame(of geometry: GeometryProxy) -> CGRect {
        let frame = geometry.frame(in: .global)
        let insets = geometry.safeAreaInsets
        return CGRect(
            x: frame.minX - insets.leading,
            y: frame.minY - insets.top,
            width: frame.width + insets.leading + insets.trailing,
            height: frame.height + insets.top + insets.bottom
        )
    }
}

struct StationRow_Previews: PreviewProvider {
    static var previews: some View {
        List {
            StationRow(title: "Keelung", subtitle: "Xinyi District, Keelung City",
                       reading: .init(aqi: 54, publishTime: "2026-08-07T22:00:00", pollutants: [
                           .init(type: .pm25, value: 18), .init(type: .pm10, value: 32), .init(type: .o3, value: 41.2),
                       ]),
                       alertsOn: true)
            StationRow(title: "Songshan", subtitle: "Songshan District, Taipei City",
                       reading: .init(aqi: 141, publishTime: "2026-08-07T22:00:00"))
            StationRow(title: "臺灣大道", subtitle: nil, reading: nil)
        }
    }
}
