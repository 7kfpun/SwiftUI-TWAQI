//
//  ProView.swift
//  TWAQI
//
//  Created by kf on 21/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import StoreKit
import SwiftUI

/// What Pro includes, then the plans. Features come first: a list of prices
/// with nothing above it doesn't say what the money buys.
struct ProView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var products: [Product] = []
    @State private var loadFailed = false
    @State private var purchasingId: String?
    @State private var purchaseFailed = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    header
                }
                .listRowBackground(Color.clear)

                Section(header: Text("Pro.features")) {
                    ForEach(ProFeature.allCases) { feature in
                        ProFeatureRow(feature: feature)
                    }
                }

                Section(header: Text("Pro.choose_plan"), footer: terms) {
                    plans
                }

                Section {
                    Button("Help.restore_purchase") {
                        Task { await restore() }
                    }
                    .disabled(purchasingId != nil)
                }
            }
            .listStyle(.insetGrouped)
            .navigationBarTitle(Text(verbatim: ""), displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .task { await load() }
            .alert("Pro.purchase_failed", isPresented: $purchaseFailed) {
                Button("OK", role: .cancel) {}
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(Color(AirStatuses.good.getColor()))

            Text("Pro.title")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Pro.subtitle")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var plans: some View {
        if products.isEmpty {
            HStack {
                Spacer()
                if loadFailed {
                    Button("Watch.retry") {
                        Task { await load() }
                    }
                } else {
                    ProgressView()
                }
                Spacer()
            }
        } else {
            ForEach(products, id: \.id) { product in
                Button {
                    Task { await buy(product) }
                } label: {
                    ProPlanRow(product: product, isPurchasing: purchasingId == product.id)
                }
                .disabled(purchasingId != nil)
            }
        }
    }

    /// Apple requires the renewal terms and both links beside a subscription offer.
    private var terms: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pro.renewal_terms")

            HStack(spacing: 16) {
                Link("Pro.terms_of_use", destination: Self.legalURL("terms.html"))
                Link("Pro.privacy_policy", destination: Self.legalURL("privacy.html"))
            }
        }
        .font(.footnote)
    }

    private static func legalURL(_ page: String) -> URL {
        let locale = Locale.isChinese ? "zh-Hant/" : ""
        return URL(string: "https://taiwanair.wahthefox.com/\(locale)\(page)")!
    }

    private func load() async {
        loadFailed = false
        do {
            products = try await IAPManager.products()
            loadFailed = products.isEmpty
        } catch {
            loadFailed = true
        }
    }

    private func buy(_ product: Product) async {
        purchasingId = product.id
        defer { purchasingId = nil }
        TrackingManager.logEvent(eventName: "user_premium_buy_product_started")

        do {
            if try await IAPManager.purchase(product) == .purchased {
                await SettingsStore.refreshPro()
                TrackingManager.logEvent(eventName: "user_premium_buy_product_done")
                dismiss()
            }
        } catch {
            TrackingManager.logEvent(eventName: "user_premium_buy_product_failed")
            purchaseFailed = true
        }
    }

    private func restore() async {
        purchasingId = ""
        defer { purchasingId = nil }
        TrackingManager.logEvent(eventName: "user_premium_restore_purchase_started")

        do {
            try await AppStore.sync()
            await SettingsStore.refreshPro()
            if UserDefaults.standard.bool(forKey: "pro") {
                TrackingManager.logEvent(eventName: "user_premium_restore_purchase_done")
                dismiss()
            } else {
                TrackingManager.logEvent(eventName: "user_premium_restore_purchase_failed")
                purchaseFailed = true
            }
        } catch {
            TrackingManager.logEvent(eventName: "user_premium_restore_purchase_failed")
            purchaseFailed = true
        }
    }
}

/// Only what Pro actually adds today. Alerts, favourites, the map and the
/// watch app itself stay free.
enum ProFeature: String, CaseIterable, Identifiable {
    case noAds
    case complications
    case widgets
    case support

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .noAds: return "rectangle.slash"
        case .complications: return "watchface.applewatch.case"
        case .widgets: return "rectangle.grid.1x2"
        case .support: return "heart"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .noAds: return "Pro.feature_no_ads"
        case .complications: return "Pro.feature_complications"
        case .widgets: return "Pro.feature_widgets"
        case .support: return "Pro.feature_support"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .noAds: return "Pro.feature_no_ads_detail"
        case .complications: return "Pro.feature_complications_detail"
        case .widgets: return "Pro.feature_widgets_detail"
        case .support: return "Pro.feature_support_detail"
        }
    }
}

private struct ProFeatureRow: View {
    var feature: ProFeature

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feature.icon)
                .font(.title3)
                .foregroundColor(Color(AirStatuses.good.getColor()))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.headline)

                Text(feature.detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProPlanRow: View {
    var product: Product
    var isPurchasing: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(product.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)

                    if product.id == IAPManager.subscriptionProductIds.last {
                        Text("Pro.best_value")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(AirStatuses.good.getColor())))
                            .foregroundColor(.white)
                    }
                }

                detail
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isPurchasing {
                ProgressView()
            } else {
                Text(product.displayPrice)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
        }
        .padding(.vertical, 4)
    }

    /// Monthly equivalent for longer plans, so they compare at a glance.
    @ViewBuilder
    private var detail: some View {
        if let months = months, months > 1 {
            let perMonth = (product.price / Decimal(months)).formatted(product.priceFormatStyle)
            Text("Pro.per_month \(perMonth)")
        } else if months == 1 {
            Text("Pro.billed_monthly")
        } else {
            Text("Pro.lifetime_detail")
        }
    }

    private var months: Int? {
        guard let period = product.subscription?.subscriptionPeriod else { return nil }
        switch period.unit {
        case .month: return period.value
        case .year: return period.value * 12
        default: return nil
        }
    }
}
