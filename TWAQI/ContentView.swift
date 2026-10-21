//
//  ContentView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            glassTabs
        } else {
            classicTabs
        }
    }

    /// Liquid Glass: the bar floats over content and shrinks while scrolling.
    /// Same order as the classic bar, Help last. The station list keeps its
    /// own search field rather than taking the system search role, which
    /// would pin it apart at the end of the bar after Help.
    @available(iOS 26.0, *)
    private var glassTabs: some View {
        TabView {
            Tab("Tabbar.main", systemImage: "map.fill") {
                MainView()
            }

            Tab("Tabbar.favourites", systemImage: "heart") {
                FavouriteListView()
            }

            Tab("Tabbar.details_list", systemImage: "list.bullet") {
                DetailsListView()
            }

            Tab("Tabbar.help", systemImage: "questionmark.circle") {
                HelpView(viewModel: .init())
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Color(0x5AC8FA))
    }

    private var classicTabs: some View {
        TabView {
            MainView()
                .tabItem {
                    Image(systemName: "map.fill")
                    Text("Tabbar.main")
            }

            FavouriteListView()
                .tabItem {
                    Image(systemName: "heart")
                    Text("Tabbar.favourites")
            }

            DetailsListView()
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("Tabbar.details_list")
            }

            HelpView(viewModel: .init())
                .tabItem {
                    Image(systemName: "questionmark.circle")
                    Text("Tabbar.help")
            }
        }
        .font(.headline)
        .accentColor(Color(0x5AC8FA))
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ForEach(["zh-Hant", "en"], id: \.self) { localIdentifier in
            ContentView()
                .environmentObject(SettingsStore())
                .environment(\.locale, .init(identifier: localIdentifier))
                .previewDisplayName(localIdentifier)
        }

    }
}
