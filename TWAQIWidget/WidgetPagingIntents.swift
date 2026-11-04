//
//  WidgetPagingIntents.swift
//  TWAQIWidget
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import AppIntents
import WidgetKit

/// The ‹ › buttons on a medium or large widget (FOX-76): stores the station
/// to show for this widget. WidgetKit reloads the widget after `perform`; that
/// reload draws from saved readings (`WidgetPaging.isTapReload`), so the page
/// changes at once, offline too.
struct ShowWidgetPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Widget.intent_page_title"
    static var isDiscoverable = false

    @Parameter(title: "Widget.intent_widget")
    var widgetKey: String

    /// Nil: back to the widget's own station.
    @Parameter(title: "Widget.station")
    var stationId: Int?

    init() {}

    init(widgetKey: String, stationId: Int?) {
        self.widgetKey = widgetKey
        self.stationId = stationId
    }

    func perform() async throws -> some IntentResult {
        let defaults = WatchStore.sharedDefaults
        let state = WidgetPageStore.state(for: widgetKey, in: defaults)
        WidgetPageStore.save(WidgetPaging.paged(state, to: stationId, now: Date()), for: widgetKey, in: defaults)
        return .result()
    }
}

/// A tap on a widget's index label (FOX-76): stores the next index for this
/// widget. Reloads like `ShowWidgetPageIntent`.
struct CycleWidgetIndexIntent: AppIntent {
    static var title: LocalizedStringResource = "Widget.intent_index_title"
    static var isDiscoverable = false

    @Parameter(title: "Widget.intent_widget")
    var widgetKey: String

    @Parameter(title: "Index")
    var index: IndexOption

    init() {}

    init(widgetKey: String, index: IndexOption) {
        self.widgetKey = widgetKey
        self.index = index
    }

    func perform() async throws -> some IntentResult {
        let defaults = WatchStore.sharedDefaults
        let state = WidgetPageStore.state(for: widgetKey, in: defaults)
        WidgetPageStore.save(
            WidgetPaging.cycled(state, to: index.airIndexType, now: Date()), for: widgetKey, in: defaults
        )
        return .result()
    }
}
