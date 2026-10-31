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
/// Stored in the app's own standard defaults. The widgets, watch and Vision
/// targets compile this file too but never see that value, so they follow
/// the system language as before.
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

    static var current: AppLanguage { stored() }

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
