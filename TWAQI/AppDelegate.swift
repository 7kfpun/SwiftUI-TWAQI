//
//  AppDelegate.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import UIKit

import Bugsnag
import FirebaseCore
import GoogleMaps
import GoogleMobileAds
import Sentry

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.

        SettingsStore.observeProTransactions()
        Task { await SettingsStore.refreshPro() }

        // Favourites saved before the widget listed them, or by an older
        // build, only reach the app group once they're mirrored.
        WidgetBridge.publish(favouriteStationIds: SettingsStore().savedFavouriteStations)

        // A device excluded from reporting (Help's hidden version toggle, or any
        // DEBUG run) starts none of the crash reporters.
        let reportsThisLaunch = !TrackingManager.isExcludedThisLaunch

        // Initialize the Bugsnag SDK.
        if reportsThisLaunch, let bugsnagApiKey = getEnv("BugsnagApiKey") {
            Bugsnag.start(withApiKey: bugsnagApiKey)
        }

        // Use Firebase library to configure APIs (Analytics and Crashlytics).
        FirebaseApp.configure()
        TrackingManager.applyExclusionAtLaunch()

        // AQI alerts go straight through APNs: the device row lives in Directus
        // and workers/twaqi-push-sender sends. The delegate is set here so a
        // tap that launched the app is not missed; permission is only asked
        // for when an alert is first switched on.
        PushManager.shared.start()

        // Initialize the Google Mobile Ads SDK.
        MobileAds.shared.start(completionHandler: nil)

        // Initialize Google Map Service
        if let gmsServicesApiKey = getEnv("GMSServicesApiKey") {
            GMSServices.provideAPIKey(gmsServicesApiKey)
        }

        // Initialize Sentry service.
        if reportsThisLaunch, let sentryDSN = getEnv("SentryDSN") {
            SentrySDK.start(options: [
                "dsn": sentryDSN,
                "debug": true,
            ])
        }

        StoreReviewHelper.incrementAppOpenedCount()
        StoreReviewHelper.checkAndAskForReview()

        return true
    }

    // MARK: Remote notifications

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushManager.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushManager.shared.didFailToRegister(error: error)
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }

}
