//
//  ExtensionDelegate.swift
//  watch Extension
//
//  Created by kf on 17/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import ClockKit
import WatchKit

class ExtensionDelegate: NSObject, WKExtensionDelegate {

    static func scheduleComplicationUpdate() {
        let currentDate = Date()
        let scheduleDate = currentDate + TimeInterval(60 * 30)  // 30 min
        print("Scheduling background refresh task at \(currentDate) for: \(scheduleDate)")
        WKExtension.shared().scheduleBackgroundRefresh(withPreferredDate: scheduleDate, userInfo: nil) { (error) in
            if let error = error {
                print("Failed to schedule background refresh: \(error.localizedDescription)")
            }
        }
    }

    static func reloadComplications() {
        let settingsStore = SettingsStore()
        let station = settingsStore.closestStation

        APIManager.getHistoricalPollutants(stationId: station.id) { result in
            switch result {
            case .success(let result):
                let historicalPollutants = result["data"] as! HistoricalPollutants

                if let latestHistoricalPollutant = historicalPollutants.last {
                    settingsStore.latestHistoricalPollutant = latestHistoricalPollutant
                }

                let complicationServer = CLKComplicationServer.sharedInstance()
                guard let complications = complicationServer.activeComplications else { return }
                for complication in complications {
                    print("UPDATE COMPLICATION")
                    complicationServer.reloadTimeline(for: complication)
                }
            case .failure(let error):
                print(error.localizedDescription)
            }
        }
    }

    func applicationDidFinishLaunching() {
        // Perform any final initialization of your application.
        ExtensionDelegate.reloadComplications()
        ExtensionDelegate.scheduleComplicationUpdate()
    }

    func applicationDidBecomeActive() {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillResignActive() {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, etc.
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        // Sent when the system needs to launch the application in the background to process tasks. Tasks arrive in a set, so loop through and process each one.
        for task in backgroundTasks {
            // Use a switch statement to check the task type
            switch task {
            case let backgroundTask as WKApplicationRefreshBackgroundTask:
                // Be sure to complete the background task once you’re done.
                ExtensionDelegate.reloadComplications()
                ExtensionDelegate.scheduleComplicationUpdate()

                backgroundTask.setTaskCompletedWithSnapshot(false)
            case let snapshotTask as WKSnapshotRefreshBackgroundTask:
                // Snapshot tasks have a unique completion call, make sure to set your expiration date
                snapshotTask.setTaskCompleted(restoredDefaultState: true, estimatedSnapshotExpiration: Date.distantFuture, userInfo: nil)
            case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
                // Be sure to complete the connectivity task once you’re done.
                connectivityTask.setTaskCompletedWithSnapshot(false)
            case let urlSessionTask as WKURLSessionRefreshBackgroundTask:
                // Be sure to complete the URL session task once you’re done.
                urlSessionTask.setTaskCompletedWithSnapshot(false)
            case let relevantShortcutTask as WKRelevantShortcutRefreshBackgroundTask:
                // Be sure to complete the relevant-shortcut task once you're done.
                relevantShortcutTask.setTaskCompletedWithSnapshot(false)
            case let intentDidRunTask as WKIntentDidRunRefreshBackgroundTask:
                // Be sure to complete the intent-did-run task once you're done.
                intentDidRunTask.setTaskCompletedWithSnapshot(false)
            default:
                // make sure to complete unhandled task types
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
