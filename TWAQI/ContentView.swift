//
//  ContentView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    /// The language chosen under Help. Watched here so a change applies at
    /// once: SwiftUI `Text("Key")` follows `\.locale`, and rebuilding the
    /// tabs refreshes text produced in code (`.localized`, the UIKit map
    /// overlay, formatters, `Locale.isChinese` names).
    @AppStorage(AppLanguage.defaultsKey) private var language: AppLanguage = .system

    /// Kept outside the rebuilt tabs so changing language stays on Help.
    @State private var selectedTab: AppTab = .main

    enum AppTab: Hashable {
        case main, favourites, detailsList, help
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                glassTabs
            } else {
                classicTabs
            }
        }
        .id(language)
        .environment(\.locale, language.locale())
        // Outside the rebuilt tabs, so a language change doesn't lose it.
        .readsFoldLine()
    }

    /// Liquid Glass: the bar floats over content and shrinks while scrolling.
    /// Same order as the classic bar, Help last. The station list keeps its
    /// own search field rather than taking the system search role, which
    /// would pin it apart at the end of the bar after Help.
    @available(iOS 26.0, *)
    private var glassTabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Tabbar.main", systemImage: "map.fill", value: AppTab.main) {
                MainView()
            }

            Tab("Tabbar.favourites", systemImage: "heart", value: AppTab.favourites) {
                FavouriteListView()
            }

            Tab("Tabbar.details_list", systemImage: "list.bullet", value: AppTab.detailsList) {
                DetailsListView()
            }

            Tab("Tabbar.help", systemImage: "questionmark.circle", value: AppTab.help) {
                HelpView(viewModel: .init())
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Color(0x5AC8FA))
    }

    private var classicTabs: some View {
        TabView(selection: $selectedTab) {
            MainView()
                .tabItem {
                    Image(systemName: "map.fill")
                    Text("Tabbar.main")
            }
            .tag(AppTab.main)

            FavouriteListView()
                .tabItem {
                    Image(systemName: "heart")
                    Text("Tabbar.favourites")
            }
            .tag(AppTab.favourites)

            DetailsListView()
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("Tabbar.details_list")
            }
            .tag(AppTab.detailsList)

            HelpView(viewModel: .init())
                .tabItem {
                    Image(systemName: "questionmark.circle")
                    Text("Tabbar.help")
            }
            .tag(AppTab.help)
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
