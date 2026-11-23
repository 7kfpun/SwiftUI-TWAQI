//
//  ForecastView.swift
//  TWAQI
//
//  Created by kf on 3/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// The Forecast tab (FOX-32): MOENV's 空品區 forecast for every area, each
/// with every day the feed has. The reader's area comes first, then the
/// favourites' areas, then the rest. Offline it shows the store's last good
/// set, else the offline empty state.
struct ForecastView: View {
    @EnvironmentObject var settings: SettingsStore
    // Owns its view model — see the note in DetailsView.
    @StateObject private var viewModel = ForecastViewModel()

    var body: some View {
        NavigationView {
            content
                .navigationBarTitle("Forecast.tab_title")
        }
        .navigationViewStyle(.stack)
        .onAppear(perform: load)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            VStack(spacing: 16) {
                advisoryBanners
                OfflineEmptyStateView(retry: load)
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .noCurrentForecast:
            VStack(spacing: 16) {
                advisoryBanners
                EmptyStateView(icon: "calendar", message: "Forecast.none_current")
                Button(action: load) {
                    Text("Offline.retry")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let areas):
            list(areas)
        }
    }

    /// Current sand/dust advisories (FOX-10), shown in every state so they
    /// don't wait on the area forecast.
    private var advisoryBanners: some View {
        ForEach(viewModel.advisories, id: \.publishTime) { advisory in
            SandstormAdvisoryBanner(advisory: advisory)
        }
    }

    private func list(_ areas: [ForecastTabArea]) -> some View {
        let shared = ForecastTabOrdering.sharedContent(areas)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                advisoryBanners

                if let shared = shared {
                    ForecastContentText(
                        content: shared,
                        translated: ForecastTabOrdering.sharedTranslation(areas, language: OnDeviceTranslation.target)
                    )
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: AreaForecastView.cornerRadius, style: .continuous))
                        .padding(.horizontal)
                }

                ForEach(areas, id: \.area) { area in
                    AreaForecastView(
                        forecast: area.forecast,
                        heading: .area(area.pin),
                        showsContent: shared == nil || area.forecast.content != shared
                    )
                }
            }
            .padding(.vertical)
        }
    }

    private func load() {
        viewModel.load(favouriteStationIds: settings.savedFavouriteStations)
    }
}

/// A MOENV sand/dust advisory (FOX-10), above the forecast cards.
struct SandstormAdvisoryBanner: View {
    let advisory: SandstormAdvisory

    private var subject: String? {
        advisory.subject?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private var content: String? {
        advisory.content?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "wind")
                    .foregroundColor(.orange)
                Group {
                    if let subject = subject {
                        Text(subject)
                    } else {
                        Text("Forecast.sandstorm_title")
                    }
                }
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            }
            if let content = content {
                ForecastContentText(content: content)
            }
            if let published = advisory.publishedAt {
                Text("Forecast.published \(AreaForecastView.publishedText(published))")
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: AreaForecastView.cornerRadius, style: .continuous))
        .padding(.horizontal)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct ForecastView_Previews: PreviewProvider {
    static var previews: some View {
        ForecastView().environmentObject(SettingsStore())
    }
}
