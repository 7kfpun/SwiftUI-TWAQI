//
//  AnalyticsTests.swift
//  TWAQITests
//
//  Created by kf on 3/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

final class AnalyticsTests: XCTestCase {
    // MARK: - Event names

    /// Firebase drops an event whose name breaks its rules, with no error at
    /// the call site: up to 40 characters, a letter first, then letters,
    /// digits and underscores, and none of the reserved prefixes.
    func testEventNamesAreValidFirebaseNames() {
        let reservedPrefixes = ["firebase_", "google_", "ga_"]
        for event in AnalyticsEvent.allCases {
            let name = event.rawValue
            XCTAssertLessThanOrEqual(name.count, 40, name)
            XCTAssertNotNil(name.range(of: "^[a-z][a-z0-9_]*$", options: .regularExpression), name)
            XCTAssertFalse(reservedPrefixes.contains { name.hasPrefix($0) }, name)
        }
    }

    func testEventNamesAreUnique() {
        let names = AnalyticsEvent.allCases.map(\.rawValue)
        XCTAssertEqual(Set(names).count, names.count)
    }

    /// Names already in Firebase keep their history only if they don't change.
    func testExistingEventNamesAreUnchanged() {
        XCTAssertEqual(AnalyticsEvent.proScreenOpened.rawValue, "pro_screen_opened")
        XCTAssertEqual(AnalyticsEvent.buyProductStarted.rawValue, "user_premium_buy_product_started")
        XCTAssertEqual(AnalyticsEvent.buyProductDone.rawValue, "user_premium_buy_product_done")
        XCTAssertEqual(AnalyticsEvent.buyProductFailed.rawValue, "user_premium_buy_product_failed")
        XCTAssertEqual(AnalyticsEvent.restorePurchaseDone.rawValue, "user_premium_restore_purchase_done")
        XCTAssertEqual(AnalyticsEvent.openFeedbackForm.rawValue, "open_feedback_form")
        XCTAssertEqual(AnalyticsEvent.submitFeedback.rawValue, "submit_feedback")
        XCTAssertEqual(AnalyticsEvent.onboardingSkipped.rawValue, "onboarding_skipped")
        XCTAssertEqual(AnalyticsEvent.onboardingCompleted.rawValue, "onboarding_completed")
        XCTAssertEqual(AnalyticsEvent.onboardingChooseStation.rawValue, "onboarding_choose_station")
        XCTAssertEqual(AnalyticsEvent.reviewRequested.rawValue, "review_requested")
        XCTAssertEqual(AnalyticsEvent.favouriteStationSaved.rawValue, "favourite_station_saved")
    }

    // MARK: - Pro funnel

    func testProScreenSourcesMatchTheFunnelNames() {
        XCTAssertEqual(ProScreenSource.helpRow.rawValue, "help_row")
        XCTAssertEqual(ProScreenSource.onboarding.rawValue, "onboarding")
        XCTAssertEqual(ProScreenSource.widgetLocked.rawValue, "widget_locked")
        XCTAssertEqual(ProScreenSource.deepLink.rawValue, "deep_link")
    }

    func testPlanNamesForEachProduct() {
        XCTAssertEqual(ProPlan(productId: "com.kfpun.twaqi.subscription.adfree.1m", lifetimeProductId: nil), .oneMonth)
        XCTAssertEqual(ProPlan(productId: "com.kfpun.twaqi.subscription.adfree.6m", lifetimeProductId: nil), .sixMonths)
        XCTAssertEqual(ProPlan(productId: "com.kfpun.twaqi.subscription.adfree.12m", lifetimeProductId: nil), .twelveMonths)
        XCTAssertEqual(ProPlan(productId: "com.example.adfree", lifetimeProductId: "com.example.adfree"), .lifetime)
        XCTAssertEqual(ProPlan(productId: "com.example.unknown", lifetimeProductId: "com.example.adfree"), .other)
        XCTAssertEqual(ProPlan.oneMonth.rawValue, "1m")
        XCTAssertEqual(ProPlan.sixMonths.rawValue, "6m")
        XCTAssertEqual(ProPlan.twelveMonths.rawValue, "12m")
    }

    /// Every product the Pro screen sells gets a plan name of its own.
    func testEverySubscriptionProductHasAPlan() {
        for productId in IAPManager.subscriptionProductIds {
            XCTAssertNotEqual(ProPlan(productId: productId, lifetimeProductId: nil), .other, productId)
        }
    }

    // MARK: - Onboarding

    func testOnboardingStepNamesAreDistinctAndOneBased() {
        let steps = Onboarding.Step.allCases
        XCTAssertEqual(Set(steps.map(\.analyticsName)).count, steps.count)
        XCTAssertEqual(steps.map(\.analyticsIndex), Array(1...steps.count))
        XCTAssertEqual(Onboarding.Step.closestStation.analyticsName, "closest_station")
    }

    // MARK: - DebugView

    func testDebugViewNeedsFirebaseDebugFlag() {
        XCTAssertTrue(TrackingManager.debugViewCollectionEnabled(arguments: ["app", "-FIRDebugEnabled"], isExcluded: false))
        XCTAssertFalse(TrackingManager.debugViewCollectionEnabled(arguments: ["app"], isExcluded: false))
        XCTAssertFalse(TrackingManager.debugViewCollectionEnabled(arguments: ["app", "-FIRDebugDisabled"], isExcluded: false))
    }

    func testDebugViewStaysOffOnAnExcludedDevice() {
        XCTAssertFalse(TrackingManager.debugViewCollectionEnabled(arguments: ["app", "-FIRDebugEnabled"], isExcluded: true))
    }
}
