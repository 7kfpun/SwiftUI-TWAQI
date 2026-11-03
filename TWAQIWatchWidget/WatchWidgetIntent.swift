//
//  WatchWidgetIntent.swift
//  TWAQIWatchWidget
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import AppIntents
import WidgetKit

// The complication's configuration. In both the widget extension and the
// watch app, which donates it to the Smart Stack (`SmartStackHints`).

/// Which index a complication shows. Mirrors `AirIndexTypes`, which can't
/// conform to `AppEnum` itself without dragging AppIntents into the iOS app.
enum IndexOption: String, AppEnum, CaseIterable {
    case aqi, pm25, pm10, o3, co, so2, no2

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Index"

    static var caseDisplayRepresentations: [IndexOption: DisplayRepresentation] = [
        .aqi: "AQI",
        .pm25: "PM2.5",
        .pm10: "PM10",
        .o3: "O3",
        .co: "CO",
        .so2: "SO2",
        .no2: "NO2",
    ]

    var airIndexType: AirIndexTypes {
        AirIndexTypes(rawValue: rawValue) ?? .aqi
    }
}

/// How a complication shows its index.
enum ComplicationStyle: String, AppEnum, CaseIterable {
    /// "AQI 42": the index name, the number and, with room, the unit.
    case labelled
    /// "42": just the number, for small slots and readers who know the index.
    case numberOnly
    /// The phone app's face for the band, with the number where it fits.
    case face
    /// "Moderate": the health level in words, no number at all.
    case status

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Style"

    static var caseDisplayRepresentations: [ComplicationStyle: DisplayRepresentation] = [
        .labelled: "With label",
        .numberOnly: "Number only",
        .face: "Face",
        .status: "Status",
    ]
}

struct SelectIndexIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Index"

    /// The watch widget's `kind`.
    static let widgetKind = "TWAQIWatchWidget"

    @Parameter(title: "Index", default: .aqi)
    var index: IndexOption

    @Parameter(title: "Style", default: .labelled)
    var style: ComplicationStyle

    /// Only the rectangular and inline slots have room for the name.
    @Parameter(title: "Show Station", default: true)
    var showsStation: Bool

    init() {}

    init(index: IndexOption, style: ComplicationStyle = .labelled, showsStation: Bool = true) {
        self.index = index
        self.style = style
        self.showsStation = showsStation
    }
}
