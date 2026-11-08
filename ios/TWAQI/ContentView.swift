//
//  ContentView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import CoreLocation
import SwiftUI
import UserNotifications

struct ContentView: View {
    /// Screens opened by URL, such as Pro from the locked widget.
    @ObservedObject var router: AppRouter

    /// Handed on to a station page opened by link, which is a sheet.
    @EnvironmentObject private var settings: SettingsStore

    /// The language chosen under Help. Watched here so a change applies at
    /// once: SwiftUI `Text("Key")` follows `\.locale`, and rebuilding the
    /// tabs refreshes text produced in code (`.localized`, the UIKit map
    /// overlay, formatters, `Locale.isChinese` names).
    @AppStorage(AppLanguage.defaultsKey) private var language: AppLanguage = .system

    /// Kept outside the rebuilt tabs so changing language stays on Help.
    @State private var selectedTab: AppTab = .main

    /// The welcome flow, opened by itself once per flow version for every
    /// user (FOX-49). Help opens it again on its own.
    @State private var showingOnboarding: Bool

    /// What's New after an update (FOX-142), once per marketing version.
    @State private var showingWhatsNew = false
    private let opensWhatsNew: Bool

    /// `opensOnboarding`: whether this scene opens the welcome flow by
    /// itself. `SceneDelegate` decides it, so it knows which scene holds the
    /// launch-time prompts back (via `Onboarding.claimLaunchFlow`). No
    /// default, so a new call site can't open the flow without owning it.
    ///
    /// `opensWhatsNew`: whether this scene may open the What's New popup
    /// (FOX-142), once the launch's permission prompts are out of the way.
    init(router: AppRouter, opensOnboarding: Bool, opensWhatsNew: Bool = false) {
        self.router = router
        self.opensWhatsNew = opensWhatsNew
        _showingOnboarding = State(initialValue: opensOnboarding)
    }

    enum AppTab: Hashable {
        case main, forecast, favourites, detailsList, help
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
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView(isLaunchFlow: true) { showingOnboarding = false }
                .environment(\.locale, language.locale())
                // Shown counts from the moment it opens, so quitting or
                // skipping it doesn't bring it back on the next launch.
                .onAppear {
                    // `onAppear` can run again for the same cover; log once.
                    if OnboardingStore().markShown() {
                        TrackingManager.logEvent(.onboardingShown, parameters: [
                            "label": "launch",
                        ])
                    }
                }
        }
        .sheet(isPresented: $showingWhatsNew) {
            if let release = WhatsNew.release(for: WhatsNew.currentVersion) {
                WhatsNewView(release: release, source: "launch") { showingWhatsNew = false }
                    .environment(\.locale, language.locale())
                    // Counts from the moment it opens, so a swipe-away
                    // doesn't bring it back on the next launch.
                    .onAppear { WhatsNewStore().markShown(WhatsNew.currentVersion) }
            }
        }
        .task { await presentWhatsNewIfDue() }
        // A station from the Control Center control or the "Open station"
        // shortcut (FOX-74), over whichever tab is showing.
        .sheet(item: $router.openedStation) { station in
            NavigationView {
                DetailsView(stationId: station.id, onClose: { router.openedStation = nil })
                    .navigationBarTitleDisplayMode(.inline)
                    .environmentObject(settings)
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .environment(\.locale, language.locale())
        }
        // On the root rather than a tab, so it opens whichever tab is showing.
        .sheet(isPresented: $router.showingPro) {
            ProView(source: router.proSource)
                .environment(\.locale, language.locale())
        }
    }

    /// Opens What's New a moment after launch, unless something else is on
    /// screen or a system permission prompt is still due. Skipped launches
    /// aren't counted; it comes on a later one.
    private func presentWhatsNewIfDue() async {
        guard opensWhatsNew else { return }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let notifications = await UNUserNotificationCenter.current().notificationSettings()
        let locationUndetermined = CLLocationManager.authorizationStatus() == .notDetermined
        guard WhatsNew.isClearOfPermissionPrompts(
            locationUndetermined: locationUndetermined,
            notificationsUndetermined: notifications.authorizationStatus == .notDetermined
        ), !showingOnboarding, router.openedStation == nil, !router.showingPro else { return }
        showingWhatsNew = true
    }

    /// Liquid Glass: the bar floats over content and shrinks while scrolling.
    /// Same order as the classic bar: Map, Forecast, Favourites, List, Help
    /// (FOX-32 put Forecast second). The station list keeps its
    /// own search field rather than taking the system search role, which
    /// would pin it apart at the end of the bar after Help.
    @available(iOS 26.0, *)
    private var glassTabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Tabbar.main", systemImage: "map.fill", value: AppTab.main) {
                MainView()
            }

            Tab("Tabbar.forecast", systemImage: "calendar", value: AppTab.forecast) {
                ForecastView()
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

            ForecastView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Tabbar.forecast")
            }
            .tag(AppTab.forecast)

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
            ContentView(router: AppRouter(), opensOnboarding: false)
                .environmentObject(SettingsStore())
                .environment(\.locale, .init(identifier: localIdentifier))
                .previewDisplayName(localIdentifier)
        }

    }
}
