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
            MainView()
                .tabItem {
                    Image(systemName: "map.fill")
                    Text("Forecast")
            }

            DetailsListView()
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("Details")
            }

            ForecastView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Forecast")
                }

            SettingsView()
                .tabItem {
                    Image(systemName: "bell")
                    Text("Settings")
                }

            HelpView()
                .tabItem {
                    Image(systemName: "questionmark.circle")
                    Text("Settings")
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
