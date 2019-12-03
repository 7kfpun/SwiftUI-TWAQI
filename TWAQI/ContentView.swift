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
        TabView {
            MainView(viewModel: .init())
                .tabItem {
                    Image(systemName: "map.fill")
                    Text("Tabbar.main")
            }

            DetailsListView()
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("Tabbar.details_list")
            }

            ForecastView(viewModel: .init())
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Tabbar.forecast")
                }

            HelpView(viewModel: .init())
                .tabItem {
                    Image(systemName: "questionmark.circle")
                    Text("Tabbar.help")
            }
        }
        .font(.headline)
        .accentColor(Color(0x5AC8FA))
        .edgesIgnoringSafeArea(.top)
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
