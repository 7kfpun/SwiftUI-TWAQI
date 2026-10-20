//
//  PaywallView.swift
//  TWAQIWatch
//
//  Created by kf on 21/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import StoreKit
import SwiftUI

/// Shown instead of the readings until the upgrade is owned.
///
/// Buying and restoring both work from the watch itself: App Review expects a
/// locked feature to be unlockable where it's locked, not only on the phone.
struct PaywallView: View {
    @ObservedObject var model: WatchModel

    @State private var product: Product?
    @State private var isWorking = false
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "applewatch")
                    .font(.largeTitle)
                    .foregroundStyle(Color(AirStatuses.good.getColor()))

                Text("Watch.pro_title")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text("Watch.pro_body")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await buy() }
                } label: {
                    if let product {
                        Text("Watch.pro_buy \(product.displayPrice)")
                    } else {
                        ProgressView()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(product == nil || isWorking)

                Button("Help.restore_purchase") {
                    Task { await restore() }
                }
                .disabled(isWorking)

                if failed {
                    Text("Watch.pro_failed")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal)
        }
        .task {
            guard let productId = WatchPro.productId else { return }
            product = try? await Product.products(for: [productId]).first
        }
    }

    private func buy() async {
        guard let product else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            if case .success(.verified(let transaction)) = try await product.purchase() {
                await transaction.finish()
            }
            // Cancelled and pending purchases simply leave the paywall up.
            await model.checkPro()
            failed = false
        } catch {
            failed = true
        }
    }

    /// Pulls in a purchase made on the phone that hasn't reached the watch yet.
    private func restore() async {
        isWorking = true
        defer { isWorking = false }

        do {
            try await AppStore.sync()
            await model.checkPro()
            failed = !model.isPro
        } catch {
            failed = true
        }
    }
}
