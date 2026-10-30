//
//  WidgetWatchGuideView.swift
//  TWAQI
//
//  Created by kf on 27/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// Home Screen and Lock Screen widgets: what they show, and how to add one.
struct WidgetGuideView: View {
    var body: some View {
        List {
            Section(header: Text("Help.widgets_shows_header")) {
                guideText("Help.widgets_shows_body")
            }

            Section(header: Text("Help.widgets_favourites_header")) {
                guideText("Help.widgets_favourites_body")
                guideText("Help.widgets_favourites_add")
                guideText("Help.widgets_favourites_offline")
            }

            Section(header: Text("Help.widgets_index_header")) {
                guideText("Help.widgets_index_body")
            }

            Section(header: Text("Help.widgets_sizes_header")) {
                guideText("Help.widgets_home_sizes")
                guideText("Help.widgets_lock_sizes")
            }

            Section(
                header: Text("Help.widgets_add_header"),
                footer: Text("Help.widgets_footer").fontWeight(.light)
            ) {
                guideText("Help.widgets_add_1")
                guideText("Help.widgets_add_2")
                guideText("Help.widgets_add_3")
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitle("Help.widgets_title", displayMode: .inline)
        .onAppear {
            TrackingManager.logEvent(eventName: "open_widget_guide")
        }
    }
}

/// The free watch app, and the Pro complications on the watch face.
struct WatchGuideView: View {
    var body: some View {
        List {
            Section(header: Text("Help.watch_app_header")) {
                guideText("Help.watch_app_body")
            }

            Section(header: Text("Help.watch_complications_header")) {
                guideText("Help.watch_complications_body")
            }

            Section(
                header: Text("Help.watch_add_header"),
                footer: Text("Help.watch_footer").fontWeight(.light)
            ) {
                guideText("Help.watch_add_1")
                guideText("Help.watch_add_2")
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitle("Help.watch_title", displayMode: .inline)
        .onAppear {
            TrackingManager.logEvent(eventName: "open_watch_guide")
        }
    }
}

private func guideText(_ key: LocalizedStringKey) -> some View {
    Text(key)
        .fontWeight(.light)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
}

struct WidgetGuideView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WidgetGuideView()
        }
    }
}

struct WatchGuideView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WatchGuideView()
        }
    }
}
