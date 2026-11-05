//
//  OnboardingAnimation.swift
//  TWAQI
//
//  Created by kf on 5/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Lottie
import SwiftUI

/// The welcome flow's Lottie animations (FOX-84), drawn for TWAQI by
/// `tools/make_onboarding_animations.py` and bundled in
/// `OnboardingAnimations/`. Nothing is downloaded.
enum OnboardingAnimation: String, CaseIterable {
    case welcome
    case location
    case closestStation = "closest_station"
    case notifications
    case more
    case success

    static let subdirectory = "OnboardingAnimations"

    var fileName: String { "onboarding_\(rawValue)" }

    /// Shown instead when the file doesn't load.
    var fallbackSymbol: String {
        switch self {
        case .welcome: return "aqi.medium"
        case .location: return "location.circle"
        case .closestStation: return "heart.circle"
        case .notifications: return "bell.badge"
        case .more: return "sparkles"
        case .success: return "checkmark.circle.fill"
        }
    }

    /// Nil when the file is missing or doesn't parse.
    func load(bundle: Bundle = .main) -> LottieAnimation? {
        LottieAnimation.named(fileName, bundle: bundle, subdirectory: Self.subdirectory)
    }
}

extension Onboarding.Step {
    /// The animation at the top of the step.
    var animation: OnboardingAnimation {
        switch self {
        case .welcome: return .welcome
        case .location: return .location
        case .closestStation: return .closestStation
        case .notifications: return .notifications
        case .more: return .more
        }
    }
}

/// One animation, played once. With Reduce Motion on it shows its last frame
/// still. Decorative: VoiceOver skips it.
struct OnboardingAnimationView: View {
    var animation: OnboardingAnimation
    var size: CGFloat
    var tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let loaded = animation.load() {
                LottieView(animation: loaded)
                    .playbackMode(reduceMotion
                        ? .paused(at: .progress(1))
                        : .playing(.fromProgress(0, toProgress: 1, loopMode: .playOnce)))
                    .resizable()
            } else {
                Image(systemName: animation.fallbackSymbol)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
                    .foregroundColor(tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
