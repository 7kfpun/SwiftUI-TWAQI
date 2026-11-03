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
import OneSignal
import Sentry
import UserNotifications

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    /// Asks for a review once the welcome flow that opened at launch is
    /// finished, skipped, or gone with its scene.
    private var reviewAfterOnboarding: NSObjectProtocol?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.

        // Before this launch is counted below: notes an install that pre-dates
        // the welcome flow, then whether the flow opens by itself this launch.
        let onboarding = OnboardingStore()
        onboarding.prepareForLaunch(hasLaunchedBefore: StoreReviewHelper.hasLaunchedBefore)
        Onboarding.isOpenAtLaunch = onboarding.showsOnLaunch

        SettingsStore.observeProTransactions()
        Task { await SettingsStore.refreshPro() }

        // Favourites saved before the widget listed them, or by an older
        // build, only reach the app group once they're mirrored.
        WidgetBridge.publish(favouriteStationIds: SettingsStore().savedFavouriteStations)
        // Likewise a language chosen under Help before the widget followed it.
        WidgetBridge.publish(appLanguage: AppLanguage.stored())

        // Offline data saved more than a week ago is never shown; delete it.
        OfflineCacheRetention.purgeInBackground()

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
        // Directus holds for this device (see `DirectusPushMirror`). OneSignal
        // stays registered with the same alert tags, ready to switch back on.
        OneSignalTags.start(launchOptions: launchOptions)
        startPush(application, promptsAtLaunch: onboarding.promptsForPushAtLaunch)

        // Initialize the Google Mobile Ads SDK.
        MobileAds.shared.start(completionHandler: nil)

        // Initialize Google Map Service
        if let gmsServicesApiKey = getEnv("GMSServicesApiKey") {
            GMSServices.provideAPIKey(gmsServicesApiKey)
        }

        // Initialize Sentry service.
        if reportsThisLaunch, let sentryDSN = getEnv("SentryDSN") {
            var sentryOptions: [String: Any] = ["dsn": sentryDSN]
            #if DEBUG
            // Verbose SDK logging is for development only.
            sentryOptions["debug"] = true
            #endif
            SentrySDK.start(options: sentryOptions)
        }

        StoreReviewHelper.incrementAppOpenedCount()
        // Not over the welcome flow: after it, so a 10/30/60/100 milestone
        // that falls on this launch isn't lost.
        if !Onboarding.isOpenAtLaunch {
            StoreReviewHelper.checkAndAskForReview()
        } else {
            reviewAfterOnboarding = NotificationCenter.default.addObserver(
                forName: Onboarding.didFinish, object: nil, queue: .main
            ) { [weak self] _ in
                self?.reviewAfterOnboarding.map(NotificationCenter.default.removeObserver)
                self?.reviewAfterOnboarding = nil
                StoreReviewHelper.checkAndAskForReview()
            }
        }

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

    /// Registers with APNs on every launch — Messaging needs the APNs token
    /// for an FCM one, and registering asks the user nothing. A fresh install
    /// is asked for permission on the welcome flow's notifications step
    /// instead, so the two prompts never stack (FOX-34); installs from before
    /// the flow are asked here, except on the launch the flow opens (FOX-49).
    /// Asking again once answered is a no-op.
    private func startPush(_ application: UIApplication, promptsAtLaunch: Bool) {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        DirectusPushMirror.shared.start()
        application.registerForRemoteNotifications()

        if promptsAtLaunch {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                if let error = error {
                    print("Notification permission request failed: \(error.localizedDescription)")
                }
                print("User accepted notifications: \(granted)")
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
    /// Alerts still show while the app is open, but leave the icon's number
    /// alone: it is cleared each time the app opens, and an alert seen in
    /// the app is already read.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Messaging.messaging().appDidReceiveMessage(notification.request.content.userInfo)
        completionHandler([.banner, .list, .sound])
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
