//
//  StationWindow.swift
//  TWAQIVision
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// A station pinned in the room: opened from a card's Details button, or by
/// dragging a station out of the map or a list and letting go.
struct StationWindow: View {
    static let id = "station"

    @Binding var stationId: Int?

    @Environment(Favourites.self) private var favourites

    var body: some View {
        NavigationStack {
            if let stationId {
                StationDetailView(stationId: stationId)
            } else {
                EmptyStateView(icon: "aqi.medium", message: "Details.select_a_station")
            }
        }
        .onContinueUserActivity(StationActivity.type) { activity in
            guard let id = StationActivity.stationId(from: activity) else { return }
            stationId = id
            // Pinning a station out into the room keeps it: it's a favourite now.
            favourites.add(id)
        }
    }
}
