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
            OfflineEmptyStateView(retry: load)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .noCurrentForecast:
            VStack(spacing: 16) {
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

    private func list(_ areas: [ForecastTabArea]) -> some View {
        let shared = ForecastTabOrdering.sharedContent(areas)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if let shared = shared {
                    ForecastContentText(content: shared)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: AreaForecastView.cornerRadius, style: .continuous))
                        .padding(.horizontal)
                }

                ForEach(areas, id: \.area) { area in
                    AreaForecastView(
                        forecast: area.forecast,
                        heading: .area(area.pin),
                        showsContent: shared == nil || area.forecast.content != shared,
                        showsSource: false
                    )
                }

                // Once for the whole list rather than under every card.
                Text("Forecast.source")
                    .font(.caption.weight(.light))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical)
        }
    }

    private func load() {
        viewModel.load(favouriteStationIds: settings.savedFavouriteStations)
    }
}

struct ForecastView_Previews: PreviewProvider {
    static var previews: some View {
        ForecastView().environmentObject(SettingsStore())
    }
}
