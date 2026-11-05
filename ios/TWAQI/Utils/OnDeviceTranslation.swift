//
//  OnDeviceTranslation.swift
//  TWAQI
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Puts Chinese-only data (MOENV's forecast text, a station's township and
/// street address) into the reader's language with Apple's on-device
/// Translation framework.
///
/// Only free text from the API goes through Translation; day names, statuses
/// and pollutants are ordinary localized strings. Chinese UIs get the original.
/// Anywhere translation can't happen (before iOS 18, language not downloaded,
/// offline without the pack, any error) the original Chinese is shown — never
/// a download prompt, and never a label saying it was translated.
enum OnDeviceTranslation {
    /// The API writes Traditional Chinese.
    static let sourceIdentifier = "zh-Hant"

    /// The language to translate into, as a bare language code ("en"), or
    /// nil when the original should show. Follows the language chosen under
    /// Help.
    static var target: String? {
        target(for: .app)
    }

    /// Language code only, so System English ("en_US") and Help → English
    /// ("en") share one cache and one language pack check.
    static func target(for locale: Locale) -> String? {
        guard !locale.isChinese else { return nil }
        let code = locale.languageCode
            ?? locale.identifier.split(whereSeparator: { $0 == "_" || $0 == "-" }).first.map(String.init)
        return (code?.isEmpty ?? true) ? nil : code
    }

    /// Drops every translation made so far, e.g. when the language changes.
    static func clearCache() {
        cache.removeAllObjects()
    }

    /// Only text with Chinese in it is worth sending; anything else (a test
    /// row in English, say) is shown as is.
    static func needsTranslation(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.properties.isIdeographic }
    }

    /// The texts worth sending, once each, in order.
    static func translatable(_ texts: [String]) -> [String] {
        var seen = Set<String>()
        return texts.filter { needsTranslation($0) && seen.insert($0).inserted }
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
        display(text, target: target)
    }

    static func display(_ text: String, target: String?) -> String {
        guard let target = target, needsTranslation(text) else { return text }
        return cached(text, target: target) ?? text
    }

    // MARK: - Long text, a sentence at a time

    /// Sentence-sized pieces of `text`, each keeping its closing punctuation,
    /// so the first few can be translated before the rest. Joined back
    /// together they are exactly `text`.
    static func segments(_ text: String) -> [String] {
        let enders: Set<Character> = ["。", "！", "？", "；", "\n"]
        var pieces: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if enders.contains(character) {
                pieces.append(current)
                current = ""
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    /// The leading segments that fill about `characters` characters of the
    /// original, always at least one. Enough to cover what a few collapsed
    /// lines show, so the reader's first glance is translated first.
    static func leadingSegments(_ segments: [String], characters: Int) -> [String] {
        var taken: [String] = []
        var count = 0
        for segment in segments {
            taken.append(segment)
            count += segment.count
            if count >= characters { break }
        }
        return taken
    }

    /// `segments` with each translated one swapped in, joined back up. A
    /// space goes between pieces once either side is a translation (English
    /// sentences need one; Chinese ones run together).
    static func display(segments: [String], target: String?) -> String {
        var result = ""
        var previousTranslated = false
        for segment in segments {
            let shown = display(segment, target: target)
            let translated = shown != segment
            if !result.isEmpty, translated || previousTranslated,
               let last = result.last, !last.isWhitespace,
               let first = shown.first, !first.isWhitespace {
                result.append(" ")
            }
            if translated {
                // Keep the original's line break, if it ended with one.
                let trailing = segment.reversed().prefix { $0.isWhitespace }
                result.append(shown.trimmingCharacters(in: .whitespacesAndNewlines))
                result.append(contentsOf: trailing.reversed())
            } else {
                result.append(shown)
            }
            previousTranslated = translated
        }
        return result
    }
}

extension View {
    /// Translates `texts` in the background and bumps `revision` once
    /// translations land in the cache, so the caller re-reads
    /// `OnDeviceTranslation.display(_:)`.
    ///
    /// Does nothing in a Chinese UI, before iOS 18, or for texts without
    /// Chinese in them. The work hangs off a background view, so `self` keeps
    /// its identity (and its state, and its `onAppear`) whatever `texts` is.
    func translatesOnDevice(_ texts: [String], revision: Binding<Int>) -> some View {
        background(OnDeviceTranslationHost(texts: OnDeviceTranslation.translatable(texts), revision: revision))
    }
}

private struct OnDeviceTranslationHost: View {
    let texts: [String]
    @Binding var revision: Int

    var body: some View {
        #if canImport(Translation)
        if #available(iOS 18.0, macOS 15.0, *),
           let target = OnDeviceTranslation.target,
           !texts.isEmpty {
            Color.clear
                .modifier(OnDeviceTranslationModifier(texts: texts, target: target, revision: $revision))
                .accessibilityHidden(true)
        } else {
            Color.clear
        }
        #else
        Color.clear
        #endif
    }
}

#if canImport(Translation)
@available(iOS 18.0, macOS 15.0, *)
private struct OnDeviceTranslationModifier: ViewModifier {
    let texts: [String]
    /// Locale identifier, also the cache key.
    let target: String
    @Binding var revision: Int

    private var source: Locale.Language { Locale.Language(identifier: OnDeviceTranslation.sourceIdentifier) }
    /// `target` is already a bare language code, the same one the cache uses.
    private var targetLanguage: Locale.Language { Locale.Language(identifier: target) }

    @State private var configuration: TranslationSession.Configuration?

    private struct TaskKey: Hashable {
        let texts: [String]
        let target: String
    }

    private var missing: [String] {
        texts.filter { OnDeviceTranslation.cached($0, target: target) == nil }
    }

    func body(content: Content) -> some View {
        content
            .task(id: TaskKey(texts: texts, target: target)) {
                guard !missing.isEmpty else { return }
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
                let batch = missing
                guard !batch.isEmpty else { return }
                let requests = batch.enumerated().map { index, text in
                    TranslationSession.Request(sourceText: text, clientIdentifier: String(index))
                }
                guard let responses = try? await session.translations(from: requests) else { return }

                var translated: [(original: String, translation: String)] = []
                for response in responses {
                    guard let id = response.clientIdentifier, let index = Int(id), batch.indices.contains(index) else { continue }
                    let text = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    translated.append((batch[index], text))
                }
                guard !translated.isEmpty else { return }
                let target = target
                await MainActor.run {
                    for item in translated {
                        OnDeviceTranslation.store(item.translation, for: item.original, target: target)
                    }
                    revision += 1
                }
            }
    }
}
#endif
