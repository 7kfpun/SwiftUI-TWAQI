//
//  LocaleExtension.swift
//  TWAQI
//
//  Created by kf on 6/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

/// The language chosen under Help, overriding the system's for this app.
///
/// Stored in the app's own standard defaults, the source of truth.
/// `WidgetBridge` mirrors it into the app group so the phone's Home Screen
/// widget, a separate process, shows the same language. The watch and Vision
/// targets compile this file too but nothing writes their app group, so they
/// follow the system language as before.
enum AppLanguage: String, CaseIterable, Identifiable {
    /// Whatever iOS gives the app.
    case system
    case traditionalChinese = "zh-Hant"
    case english = "en"

    static let defaultsKey = "appLanguage"

    var id: String { rawValue }

    /// The `.lproj` / locale identifier, or nil to follow the system.
    var localeIdentifier: String? {
        self == .system ? nil : rawValue
    }

    static func stored(in defaults: UserDefaults = .standard) -> AppLanguage {
        defaults.string(forKey: defaultsKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// The app reads its own defaults; an extension (the widget) reads the
    /// mirror in the app group, since it can't see the app's defaults.
    static var current: AppLanguage {
        current(own: .standard, shared: shared, isExtension: isAppExtension)
    }

    static func current(own: UserDefaults, shared: UserDefaults, isExtension: Bool) -> AppLanguage {
        stored(in: isExtension ? shared : own)
    }

    /// The app group defaults the widget reads, under the same key.
    static var shared: UserDefaults {
        UserDefaults(suiteName: WatchStore.appGroup) ?? .standard
    }

    /// Writes `language` into `shared` the way `SettingsStore` writes its own
    /// defaults: `.system` removes the key. Returns whether anything changed.
    @discardableResult
    static func mirror(_ language: AppLanguage, to shared: UserDefaults) -> Bool {
        guard stored(in: shared) != language else { return false }
        if let identifier = language.localeIdentifier {
            shared.set(identifier, forKey: defaultsKey)
        } else {
            shared.removeObject(forKey: defaultsKey)
        }
        return true
    }

    private static let isAppExtension = Bundle.main.bundlePath.hasSuffix(".appex")

    /// The locale this choice resolves to; `.system` gives `system` back.
    func locale(system: Locale = .current) -> Locale {
        localeIdentifier.map(Locale.init(identifier:)) ?? system
    }
}

extension Locale {
    /// The locale the app is showing: the Help choice, else the system's.
    /// Use this, not `Locale.current`, for anything the reader sees.
    static var app: Locale {
        AppLanguage.current.locale()
    }

    static var isChinese: Bool {
        app.isChinese
    }

    var isChinese: Bool {
        guard let languageCode = languageCode else { return false }
        return languageCode.hasPrefix("zh")
    }
}

extension Bundle {
    /// The `.lproj` for the language chosen under Help, or the main bundle
    /// (system language) when none is chosen or it does not ship.
    ///
    /// SwiftUI `Text("Key")` already follows `\.locale` in the environment;
    /// this is for strings looked up in code (`.localized`, UIKit labels).
    /// Other targets never store a choice, so they get `.main`.
    static var appLanguage: Bundle {
        guard let identifier = AppLanguage.current.localeIdentifier else { return .main }
        return localized(identifier) ?? .main
    }

    private static var lprojs: [String: Bundle] = [:]
    private static let lprojsLock = NSLock()

    private static func localized(_ identifier: String) -> Bundle? {
        lprojsLock.lock()
        defer { lprojsLock.unlock() }
        if let bundle = lprojs[identifier] { return bundle }
        guard let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        lprojs[identifier] = bundle
        return bundle
    }
}
