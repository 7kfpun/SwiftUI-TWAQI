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
import OneSignal
import Sentry
import SwiftDate

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.

        SettingsStore.observeProTransactions()
        Task { await SettingsStore.refreshPro() }

        // Favourites saved before the widget listed them, or by an older
        // build, only reach the app group once they're mirrored.
        WidgetBridge.publish(favouriteStationIds: SettingsStore().savedFavouriteStations)

        // Offline data saved more than a week ago is never shown; delete it.
        OfflineCacheRetention.purgeInBackground()

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

        // Push is owned entirely by OneSignal below — it prompts for permission
        // and registers with APNs itself. Firebase Messaging was a second,
        // redundant path to the same thing.

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

        // Initialize OneSignal push services.
        if let oneSignalAppId = getEnv("OneSignalAppId") {
            OneSignal.initWithLaunchOptions(launchOptions)
            OneSignal.setAppId(oneSignalAppId)

            OneSignal.promptForPushNotifications(userResponse: { accepted in
                print("User accepted notifications: \(accepted)")
            })

            OneSignalManager.getOneSignalSettings { result in
                // OneSignal calls back off the main thread; writing UserDefaults
                // here fires SettingsStore's publisher on that thread too.
                DispatchQueue.main.async {
                    switch result {
                    case .success(let result):
                        print(result)
                        let settings = SettingsStore()
                        if let isDndEnabled = result.isDndEnabled, isDndEnabled != settings.isDndEnabled {
                            settings.isDndEnabled = isDndEnabled
                        }

                        if let dndStartTime = result.dndStartTime {
                            var components = DateComponents()
                            components.hour = Int(dndStartTime / 60)
                            components.minute = dndStartTime % 60
                            settings.dndStartTime = NSCalendar.current.date(from: components) ?? Date()
                        }

                        if let dndEndTime = result.dndEndTime {
                            var components = DateComponents()
                            components.hour = Int(dndEndTime / 60)
                            components.minute = dndEndTime % 60
                            settings.dndEndTime = NSCalendar.current.date(from: components) ?? Date() + 2.hours
                        }

                    case .failure(let error):
                        print(error.localizedDescription)
                    }
                }
            }

            // Copies alert settings to Directus alongside OneSignal's tags,
            // using the APNs token OneSignal registered.
            DirectusPushMirror.shared.start()
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

}
