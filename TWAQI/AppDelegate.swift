//
//  AppDelegate.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import UIKit

import Amplitude_iOS
import AppCenter
import AppCenterAnalytics
import AppCenterCrashes
import AppCenterPush
import Bugsnag
import Firebase
import GoogleMaps
import OneSignal
import Sentry
import SwiftDate

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.

        // Initialize the Amplitude SDK.
        if let amplitudeApiKey = getEnv("AmplitudeApiKey") {
            Amplitude.instance().trackingSessionEvents = true
            Amplitude.instance().initializeApiKey(amplitudeApiKey)
        }

        // Initialize the Bugsnag SDK.
        if let bugsnagApiKey = getEnv("BugsnagApiKey") {
            Bugsnag.start(withApiKey: bugsnagApiKey)
        }

        // Use Firebase library to configure APIs.
        FirebaseApp.configure()
        // [START set_messaging_delegate]
        Messaging.messaging().delegate = self as? MessagingDelegate
        // [END set_messaging_delegate]
        // Register for remote notifications. This shows a permission dialog on first run, to
        // show the dialog at a more appropriate time move this registration accordingly.
        // [START register_for_notifications]
        if #available(iOS 10.0, *) {
            // For iOS 10 display notification (sent via APNS)
            UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate

            let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
            UNUserNotificationCenter.current().requestAuthorization(
                options: authOptions,
                completionHandler: {_, _ in })
        } else {
            let settings: UIUserNotificationSettings =
            UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
            application.registerUserNotificationSettings(settings)
        }
        application.registerForRemoteNotifications()
        // [END register_for_notifications]

        // Initialize the Google Mobile Ads SDK.
        GADMobileAds.sharedInstance().start(completionHandler: nil)

        // Initialize Google Map Service
        if let gmsServicesApiKey = getEnv("GMSServicesApiKey") {
            GMSServices.provideAPIKey(gmsServicesApiKey)
        }

        // Initialize App Center services.
        if let appCenterAppSecret = getEnv("AppCenterAppSecret") {
            MSAppCenter.start(appCenterAppSecret, withServices: [
                MSAnalytics.self,
                MSCrashes.self,
                MSPush.self,
            ])
        }

        // Initialize Sentry service.
        if let sentryDSN = getEnv("SentryDSN") {
            SentrySDK.start(options: [
                "dsn": sentryDSN,
                "debug": true,
            ])
        }

        // Initialize OneSignal push services.
        if let oneSignalAppId = getEnv("OneSignalAppId") {
            let onesignalInitSettings = [kOSSettingsKeyAutoPrompt: false]
            OneSignal.initWithLaunchOptions(
                launchOptions,
                appId: oneSignalAppId,
                handleNotificationAction: nil,
                settings: onesignalInitSettings
            )

            OneSignal.inFocusDisplayType = OSNotificationDisplayType.notification

            // TODO: Recommend moving the below line to prompt for push after informing the user about
            // how your app will use them.
            OneSignal.promptForPushNotifications(userResponse: { accepted in
                print("User accepted notifications: \(accepted)")
            })

            OneSignalManager.getOneSignalSettings { result in
                switch result {
                case .success(let result):
                    print(result)
                    let settings = SettingsStore()
                    if let isForecastEnabled = result.isForecastEnabled, isForecastEnabled != settings.isForecastEnabled {
                        settings.isForecastEnabled = isForecastEnabled
                    }

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
