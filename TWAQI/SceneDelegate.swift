//
//  SceneDelegate.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import UIKit
import SwiftUI
import UserNotifications

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    private let settings = SettingsStore()
    private let router = AppRouter()

    /// A URL that arrived before the scene was active: a cold start from the
    /// widget, or a tap while the app was in the background. Opened in
    /// `sceneDidBecomeActive`, once the window can present.
    private var pendingURL: URL?

    /// This scene opened the welcome flow by itself (FOX-49).
    private var opensOnboarding = false

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).

        // Create the SwiftUI view that provides the window contents.
        opensOnboarding = Onboarding.claimLaunchFlow(showsOnLaunch: OnboardingStore().showsOnLaunch)
        let contentView = ContentView(router: router, opensOnboarding: opensOnboarding)

        // Use a UIHostingController as window root view controller.
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = UIHostingController(
                rootView: contentView.environmentObject(settings)
            )
            self.window = window
            window.makeKeyAndVisible()
        }

        // Launched by a URL, e.g. a tap on the locked Pro widget.
        pendingURL = connectionOptions.urlContexts.first?.url

        // An opaque background would cover the Liquid Glass tab bar on iOS 26.
        if #unavailable(iOS 26.0) {
            UITabBar.appearance().backgroundColor = UIColor.systemBackground
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not neccessarily discarded (see `application:didDiscardSceneSessions` instead).

        // The welcome flow goes with this scene without being finished, and
        // it was already marked shown, so no other scene will open it: let
        // the prompts it held back (the map's location, the review) go ahead.
        if opensOnboarding {
            Onboarding.releaseLaunchHold()
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
        Self.clearBadge()
        if let url = pendingURL {
            pendingURL = nil
            open(url)
        }
    }

    /// Opening the app reads its alerts, so the number on the icon goes.
    /// OneSignal's SDK did this before FOX-13; nothing else does now.
    static func clearBadge() {
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        if scene.activationState == .foregroundActive {
            open(url)
        } else {
            pendingURL = url
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
        // A subscription may have lapsed or renewed while the app was away.
        Task { await SettingsStore.refreshPro() }
        // Back online, perhaps: alert changes Directus hasn't taken yet.
        Task { @MainActor in
            DirectusPushMirror.shared.start()
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }

    /// Hands `url` to the router. The Pro screen is a sheet on the root view,
    /// so a sheet left open (a station, Help's own Pro screen, a share sheet)
    /// is closed first; otherwise the new one could not be shown.
    private func open(_ url: URL) {
        let isPro = settings.isPro
        guard DeepLink.route(url, isPro: isPro) != nil,
              !router.showingPro,
              let root = window?.rootViewController,
              root.presentedViewController != nil
        else {
            router.open(url, isPro: isPro)
            return
        }
        root.dismiss(animated: false) { [router] in
            router.open(url, isPro: isPro)
        }
    }

}
