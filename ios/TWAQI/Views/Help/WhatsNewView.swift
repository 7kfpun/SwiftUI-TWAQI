//
//  WhatsNewView.swift
//  TWAQI
//
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// The What's New sheet (FOX-142): a title, a few bullets and a Close
/// button. No paywall: a Pro bullet is only labelled.
struct WhatsNewView: View {
    let release: WhatsNew.Release
    /// `launch` or `help`, for analytics.
    let source: String
    var onClose: () -> Void

    @State private var didLogShown = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // The welcome flow's sparkles Lottie (FOX-84), played once;
                // still under Reduce Motion, skipped by VoiceOver.
                OnboardingAnimationView(animation: .more, size: 120, tint: .accentColor)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 4) {
                    Text("WhatsNew.title")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                }

                ForEach(release.items, id: \.titleKey) { item in
                    row(item)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onClose) {
                Text("WhatsNew.close")
                    .font(.headline)
                    .frame(maxWidth: 560)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .background(Color.accentColor)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color(UIColor.systemBackground))
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .onAppear {
            // `onAppear` can run again for the same sheet; log once.
            guard !didLogShown else { return }
            didLogShown = true
            TrackingManager.logEvent(.whatsNewShown, parameters: [
                "label": source,
                "version": release.version,
            ])
        }
        .onDisappear {
            TrackingManager.logEvent(.whatsNewDismissed, parameters: [
                "label": source,
                "version": release.version,
            ])
        }
    }

    private func row(_ item: WhatsNew.Item) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: item.icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(LocalizedStringKey(item.titleKey))
                        .font(.headline)
                    if item.isPro {
                        Text("WhatsNew.pro")
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(6)
                    }
                }
                Text(LocalizedStringKey(item.bodyKey))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
