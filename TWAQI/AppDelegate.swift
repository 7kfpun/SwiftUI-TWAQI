//
//  AppDelegate.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import UIKit

import AppCenter
import AppCenterAnalytics
import AppCenterCrashes
import AppCenterPush
import Bugsnag
import Firebase
import GoogleMaps
import OneSignal

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.

        // Initialize the Bugsnag SDK.
        if let bugsnagApiKey = getEnv("BugsnagApiKey") {
            Bugsnag.start(withApiKey: bugsnagApiKey)
        }

        // Use Firebase library to configure APIs.
        FirebaseApp.configure()

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

}
