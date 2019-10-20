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
                    Text("Forecast")
            }

            DetailsListView()
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("Details")
            }

            ForecastView(viewModel: .init())
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Forecast")
                }

            SettingsView(viewModel: .init())
                .tabItem {
                    Image(systemName: "bell")
                    Text("Settings")
                }

            HelpView()
                .tabItem {
                    Image(systemName: "questionmark.circle")
                    Text("Help")
            }
        }
        .font(.headline)
        .accentColor(Color(0x5AC8FA))
        .edgesIgnoringSafeArea(.top)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
