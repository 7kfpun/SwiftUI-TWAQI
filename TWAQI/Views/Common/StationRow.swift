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

    struct Reading {
        var aqi: Double
        var publishTime: String?
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .fontWeight(.light)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
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

/// Navigation for the station lists. In a wide window — iPad, an unfolded
/// foldable, a large split-screen window — the list and the chosen station sit
/// side by side; in a narrow one it is the usual push stack. Follows the
/// window as it resizes.
struct AdaptiveNavigation<Sidebar: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let sidebar: Sidebar

    init(@ViewBuilder sidebar: () -> Sidebar) {
        self.sidebar = sidebar()
    }

    var body: some View {
        if horizontalSizeClass == .regular {
            if #available(iOS 16.0, *) {
                // Both columns always: a hideable list would leave an iPad in
                // portrait opening on an empty "select a station" page.
                NavigationSplitView(columnVisibility: .constant(.all)) {
                    if #available(iOS 17.0, *) {
                        sidebar.toolbar(removing: .sidebarToggle)
                    } else {
                        sidebar
                    }
                } detail: {
                    noSelection
                }
                .navigationSplitViewStyle(.balanced)
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

    private var noSelection: some View {
        EmptyStateView(icon: "aqi.medium", message: "Details.select_a_station")
    }
}

struct StationRow_Previews: PreviewProvider {
    static var previews: some View {
        List {
            StationRow(title: "Keelung", subtitle: "Xinyi District, Keelung City",
                       reading: .init(aqi: 54, publishTime: "2026-08-07T22:00:00"))
            StationRow(title: "Songshan", subtitle: "Songshan District, Taipei City",
                       reading: .init(aqi: 141, publishTime: "2026-08-07T22:00:00"))
            StationRow(title: "臺灣大道", subtitle: nil, reading: nil)
        }
    }
}
