//
//  PaywallView.swift
//  TWAQIWatch
//
//  Created by kf on 21/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import StoreKit
import SwiftUI

/// Pro on the watch: the app is free, the watch-face complications are not.
///
/// Buying and restoring both work from the watch itself: App Review expects a
/// locked feature to be unlockable where it's locked, not only on the phone.
struct PaywallView: View {
    @ObservedObject var model: WatchModel
    @Environment(\.dismiss) private var dismiss

    @State private var products: [Product] = []
    @State private var purchasingId: String?
    @State private var failed = false

    /// What Pro adds on the watch; the phone's Pro screen lists the full set.
    private static let features: [(icon: String, title: LocalizedStringKey)] = [
        ("watchface.applewatch.case", "Watch.pro_feature_complications"),
        ("square.grid.2x2", "Watch.pro_feature_indices"),
        ("rectangle.slash", "Watch.pro_feature_no_ads"),
    ]

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Image(systemName: "watchface.applewatch.case")
                        .font(.title)
                        .foregroundStyle(Color(AirStatuses.good.getColor()))

                    Text("Watch.pro_title")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(Self.features, id: \.icon) { feature in
                    Label(feature.title, systemImage: feature.icon)
                        .font(.footnote)
                }
            }

            Section {
                if products.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(products, id: \.id) { product in
                        Button {
                            Task { await buy(product) }
                        } label: {
                            HStack {
                                Text(product.displayName)
                                    .font(.footnote)
                                Spacer()
                                if purchasingId == product.id {
                                    ProgressView()
                                        .frame(width: 20)
                                } else {
                                    Text(product.displayPrice)
                                        .font(.footnote)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .disabled(purchasingId != nil)
                    }
                }
            } footer: {
                Text("Pro.renewal_terms")
            }

            Section {
                Button("Help.restore_purchase") {
                    Task { await restore() }
                }
                .disabled(purchasingId != nil)

                if failed {
                    Text("Watch.pro_failed")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            products = (try? await IAPManager.products()) ?? []
        }
    }

    private func buy(_ product: Product) async {
        purchasingId = product.id
        defer { purchasingId = nil }

        do {
            // Cancelled and pending purchases simply leave the paywall up.
            _ = try await IAPManager.purchase(product)
            await model.checkPro()
            failed = false
            if model.isPro {
                dismiss()
            }
        } catch {
            failed = true
        }
    }

    /// Pulls in a purchase made on the phone that hasn't reached the watch yet.
    private func restore() async {
        purchasingId = ""
        defer { purchasingId = nil }

        do {
            try await AppStore.sync()
            await model.checkPro()
            failed = !model.isPro
            if model.isPro {
                dismiss()
            }
        } catch {
            failed = true
        }
    }
}
