//
//  ComplicationController.swift
//  watch Extension
//
//  Created by kf on 23/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Alamofire
import ClockKit
import WatchKit

class ComplicationController: NSObject, CLKComplicationDataSource {

    let defaults = UserDefaults.standard

    // MARK: - Timeline Configuration
    
    func getSupportedTimeTravelDirections(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimeTravelDirections) -> Void) {
        handler([.forward, .backward])
    }
    
    func getTimelineStartDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        handler(nil)
    }
    
    func getTimelineEndDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        handler(nil)
    }
    
    func getPrivacyBehavior(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void) {
        handler(.showOnLockScreen)
    }
    
    func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {
        // Call the handler with the current timeline entry
        let station = defaults.structData(Station.self, forKey: "closestStation")
            ?? Station(name: "Matsu", nameLocal: "馬祖", lon: 119.949875, lat: 26.160469)

        HistoryPollutantManager.getHistory(nameLocal: station.nameLocal) { result in
            switch result {
            case .success(let historyPollutants):
                if let lastHistoryPollutant = historyPollutants.last,
                    let template = self.getDummyTemplate(for: complication, station: station, historyPollutant: lastHistoryPollutant) {
                    let entry = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template)
                    handler(entry)
                } else {
                    handler(nil)
                }
            case .failure(let error):
                print(error)
                handler(nil)
            }
        }
    }
    
    func getTimelineEntries(for complication: CLKComplication, before date: Date, limit: Int, withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
        // Call the handler with the timeline entries prior to the given date
        handler(nil)
    }
    
    func getTimelineEntries(for complication: CLKComplication, after date: Date, limit: Int, withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
        // Call the handler with the timeline entries after to the given date
        handler(nil)
    }
    
    // MARK: - Placeholder Templates
    
    func getLocalizableSampleTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
        // This method will be called once per supported complication, and the results will be cached
        let station = defaults.structData(Station.self, forKey: "closestStation") ?? Station(name: "Matsu", nameLocal: "馬祖", lon: 119.949875, lat: 26.160469)

        let historyPollutant = HistoryPollutant(
            stationId: 56,
            aqi: 61,
            pm25: 32,
            pm10: 26,
            no2: 5.7,
            so2: 2.3,
            co: 0.25,
            o3: 39,
            publishTime: "2019-10-13T04:00:00"
        )

        if let template = getDummyTemplate(for: complication, station: station, historyPollutant: historyPollutant) {
            handler(template)
        } else {
            handler(nil)
        }
    }

    private func getDummyTemplate(for complication: CLKComplication, station: Station, historyPollutant: HistoryPollutant) -> CLKComplicationTemplate? {
        let template: CLKComplicationTemplate

        switch complication.family {
        case .modularSmall:
            print("modularSmall")
            let modularSmallTemplate = CLKComplicationTemplateModularSmallStackText()
            modularSmallTemplate.line1TextProvider = CLKSimpleTextProvider(text: "AQI")
            modularSmallTemplate.line2TextProvider = CLKSimpleTextProvider(text: "M\(historyPollutant.aqi)")
            template = modularSmallTemplate
            template.tintColor = .white
            return template
        case .modularLarge:
            print("modularLarge")
            let modularLargeTemplate = CLKComplicationTemplateModularLargeStandardBody()
            modularLargeTemplate.headerTextProvider = CLKSimpleTextProvider(text: "2 PRs waiting")
            modularLargeTemplate.body1TextProvider = CLKSimpleTextProvider(text: "#6 Create Watch App")
            modularLargeTemplate.body2TextProvider = CLKSimpleTextProvider(text: "\(Int.random(in: 0 ..< 10))")
            template = modularLargeTemplate
            template.tintColor = .white
            return template
        case .utilitarianSmall, .utilitarianSmallFlat:
            print(".utilitarianSmall, .utilitarianSmallFlat")
            let utilitarianSmallTemplate = CLKComplicationTemplateUtilitarianSmallFlat()
            utilitarianSmallTemplate.textProvider = CLKSimpleTextProvider(text: "AQI \(historyPollutant.aqi)")
            template = utilitarianSmallTemplate
            template.tintColor = .white
            return template
        case .utilitarianLarge:
            print(".utilitarianLarge")
            let utilitarianLargeTemplate = CLKComplicationTemplateUtilitarianLargeFlat()
            utilitarianLargeTemplate.textProvider = CLKSimpleTextProvider(text: "AQI \(historyPollutant.aqi)")
            template = utilitarianLargeTemplate
            template.tintColor = .white
            return template
        case .circularSmall:
            print(".circularSmall")
            let circularSmallTemplate = CLKComplicationTemplateCircularSmallStackText()
            circularSmallTemplate.line1TextProvider = CLKSimpleTextProvider(text: "AQI")
            circularSmallTemplate.line2TextProvider = CLKSimpleTextProvider(text: "C\(historyPollutant.aqi)")
            template = circularSmallTemplate
            template.tintColor = .white
            return template
        case .extraLarge:
            print(".extraLarge")
            let extraLargeTemplate = CLKComplicationTemplateExtraLargeStackText()
            extraLargeTemplate.line1TextProvider = CLKSimpleTextProvider(text: "AQI")
            extraLargeTemplate.line2TextProvider = CLKSimpleTextProvider(text: "W\(historyPollutant.aqi)")
            template = extraLargeTemplate
            template.tintColor = .white
            return template
        case .graphicCorner:
            print(".graphicCorner")
            let graphicCornerTemplate = CLKComplicationTemplateGraphicCornerStackText()
            graphicCornerTemplate.innerTextProvider = CLKSimpleTextProvider(text: "AQI \(historyPollutant.aqi) PM2.5 \(historyPollutant.pm25)")
            graphicCornerTemplate.outerTextProvider = CLKSimpleTextProvider(text: station.nameLocal)
            template = graphicCornerTemplate
            template.tintColor = .white
            return template
        case .graphicBezel:
            print(".graphicBezel")
            let gaugeProvider = CLKSimpleGaugeProvider(style: .ring, gaugeColor: .green, fillFraction: Float(historyPollutant.aqi / 500))

            let graphicCircularTemplate = CLKComplicationTemplateGraphicCircularOpenGaugeSimpleText()
            graphicCircularTemplate.bottomTextProvider = CLKSimpleTextProvider(text: "AQI")
            graphicCircularTemplate.centerTextProvider = CLKSimpleTextProvider(text: "\(historyPollutant.aqi)")
            graphicCircularTemplate.gaugeProvider = gaugeProvider

            let graphicBezelTemplate = CLKComplicationTemplateGraphicBezelCircularText()
            graphicBezelTemplate.circularTemplate = graphicCircularTemplate
            template = graphicBezelTemplate
            template.tintColor = .white
            return template
        case .graphicCircular:
            print(".graphicCircular")
            let gaugeProvider = CLKSimpleGaugeProvider(style: .ring, gaugeColor: .green, fillFraction: Float(historyPollutant.aqi / 500))

            let template = CLKComplicationTemplateGraphicCircularClosedGaugeText()
            template.centerTextProvider = CLKSimpleTextProvider(text: "222")
            template.gaugeProvider = gaugeProvider
            return template

        case .graphicRectangular:
            print(".graphicRectangular")
            let graphicRectangularTemplate = CLKComplicationTemplateGraphicRectangularStandardBody()
            graphicRectangularTemplate.headerTextProvider = CLKSimpleTextProvider(text: "2 PRs waiting")
            graphicRectangularTemplate.body1TextProvider = CLKSimpleTextProvider(text: "#6 Create Watch App")
            graphicRectangularTemplate.body2TextProvider = CLKSimpleTextProvider(text: "\(Int.random(in: 0 ..< 10)) • Arclite")
            template = graphicRectangularTemplate
            template.tintColor = .white
            return template
        default:
            return nil
        }
    }
}
