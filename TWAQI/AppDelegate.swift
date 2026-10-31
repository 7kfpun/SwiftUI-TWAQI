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
import FirebaseMessaging
import GoogleMaps
import GoogleMobileAds
import Sentry
import UserNotifications

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

        // Use Firebase library to configure APIs (Analytics, Crashlytics and
        // Messaging).
        FirebaseApp.configure()
        TrackingManager.applyExclusionAtLaunch()

        // Push: alerts are sent through Firebase Cloud Messaging to the token
        // Directus holds for this device (see `DirectusPushMirror`).
        startPush(application)

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

    // MARK: Push

    /// Asks for permission at launch, as the app always has, and registers
    /// with APNs either way: Messaging needs the APNs token for an FCM one.
    private func startPush(_ application: UIApplication) {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        DirectusPushMirror.shared.start()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("Notification permission request failed: \(error.localizedDescription)")
            }
            print("User accepted notifications: \(granted)")
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        DirectusPushMirror.shared.apnsTokenChanged(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed: \(error.localizedDescription)")
    }
}

extension AppDelegate: MessagingDelegate {
    /// At launch, and whenever FCM issues a new token.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            DirectusPushMirror.shared.fcmTokenChanged(fcmToken)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Alerts still show while the app is open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Messaging.messaging().appDidReceiveMessage(notification.request.content.userInfo)
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Messaging.messaging().appDidReceiveMessage(response.notification.request.content.userInfo)
        completionHandler()
    }
}
