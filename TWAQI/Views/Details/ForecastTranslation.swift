//
//  ForecastTranslation.swift
//  TWAQI
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Puts MOENV's Chinese forecast text into the reader's language with Apple's
/// on-device Translation framework.
///
/// Only the free text goes through Translation; day names, statuses and
/// pollutants are ordinary localized strings. Chinese UIs get the original.
/// Anywhere translation can't happen (before iOS 18, language not downloaded,
/// any error) the original Chinese is shown — never a download prompt, and
/// never a label saying it was translated.
enum ForecastTranslation {
    /// MOENV writes Traditional Chinese.
    static let sourceIdentifier = "zh-Hant"

    /// The reader's locale to translate into, e.g. "en_US", or nil when the
    /// original should show.
    static var target: String? {
        Locale.isChinese ? nil : Locale.current.identifier
    }

    /// Only text with Chinese in it is worth sending; anything else (a test
    /// row in English, say) is shown as is.
    static func needsTranslation(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.properties.isIdeographic }
    }

    /// Translations already made this launch, by target language and source
    /// text, so a screen reopened or re-rendered does not translate again.
    private static let cache = NSCache<NSString, NSString>()

    private static func key(_ text: String, _ target: String) -> NSString {
        "\(target)\u{1F}\(text)" as NSString
    }

    static func cached(_ text: String, target: String) -> String? {
        cache.object(forKey: key(text, target)) as String?
    }

    static func store(_ translation: String, for text: String, target: String) {
        cache.setObject(translation as NSString, forKey: key(text, target))
    }

    /// What to show for `text` right now: a cached translation, else the original.
    static func display(_ text: String) -> String {
        guard let target = target, needsTranslation(text) else { return text }
        return cached(text, target: target) ?? text
    }
}

extension View {
    /// Translates `text` in the background and bumps `revision` once a
    /// translation lands in the cache, so the caller re-reads
    /// `ForecastTranslation.display(text)`.
    @ViewBuilder
    func translatesForecast(_ text: String, revision: Binding<Int>) -> some View {
        #if canImport(Translation)
        if #available(iOS 18.0, macOS 15.0, *),
           let target = ForecastTranslation.target,
           ForecastTranslation.needsTranslation(text) {
            modifier(ForecastTranslationModifier(text: text, target: target, revision: revision))
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if canImport(Translation)
@available(iOS 18.0, macOS 15.0, *)
private struct ForecastTranslationModifier: ViewModifier {
    let text: String
    /// Locale identifier, also the cache key.
    let target: String
    @Binding var revision: Int

    private var source: Locale.Language { Locale.Language(identifier: ForecastTranslation.sourceIdentifier) }
    private var targetLanguage: Locale.Language { Locale(identifier: target).language }

    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .task(id: text) {
                guard ForecastTranslation.cached(text, target: target) == nil else { return }
                // Translate only with languages already on the device: with a
                // missing pack, `translate` would put up a download sheet.
                let status = await LanguageAvailability().status(from: source, to: targetLanguage)
                guard status == .installed else { return }

                if configuration == nil {
                    configuration = TranslationSession.Configuration(source: source, target: targetLanguage)
                } else {
                    // Same languages, new text: run the task again.
                    configuration?.invalidate()
                }
            }
            .translationTask(configuration) { session in
                let original = text
                guard let response = try? await session.translate(original) else { return }
                let translated = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translated.isEmpty else { return }
                await MainActor.run {
                    ForecastTranslation.store(translated, for: original, target: target)
                    revision += 1
                }
            }
    }
}
#endif
