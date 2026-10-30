//
//  SceneDelegate.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import SwiftUI
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    private var pushTaps: AnyCancellable?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).

        // Create the SwiftUI view that provides the window contents.
        let contentView = ContentView()

        // Use a UIHostingController as window root view controller.
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            let settings = SettingsStore()
            window.rootViewController = UIHostingController(
                rootView: contentView.environmentObject(settings)
            )
            self.window = window
            window.makeKeyAndVisible()
        }

        // A tapped alert opens its station over whatever is showing. Also
        // delivers the tap that launched the app, which can arrive first.
        pushTaps = PushManager.shared.$pendingStationId
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stationId in
                PushManager.shared.pendingStationId = nil
                self?.openStation(stationId)
            }

        // An opaque background would cover the Liquid Glass tab bar on iOS 26.
        if #unavailable(iOS 26.0) {
            UITabBar.appearance().backgroundColor = UIColor.systemBackground
        }
    }

    /// Same presentation as tapping a map marker on a phone: the station in a
    /// sheet with a Done button.
    private func openStation(_ stationId: Int) {
        guard var top = window?.rootViewController else { return }
        while let presented = top.presentedViewController {
            top = presented
        }

        let details = UIHostingController(rootView: DetailsView(stationId: stationId).environmentObject(SettingsStore()))
        details.navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak details] _ in details?.dismiss(animated: true) }
        )
        top.present(UINavigationController(rootViewController: details), animated: true)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not neccessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
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
        // Notifications may have been switched on or off in Settings; also
        // refreshes the device's last_seen_at.
        PushManager.shared.refresh()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }

}
