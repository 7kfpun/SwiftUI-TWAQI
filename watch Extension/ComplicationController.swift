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

    func getNextRequestedUpdateDateWithHandler(handler: (NSDate?) -> Void) {
        // Update hourly
        // https://stackoverflow.com/questions/37819483/watchos-show-realtime-departure-data-on-complication
        handler(NSDate(timeIntervalSinceNow: 0.01))
    }

    func getTimelineStartDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        let currentDate = Date()
        handler(currentDate)
    }
    
    func getTimelineEndDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        let currentDate = Date()
        let endDate = currentDate.addingTimeInterval(1)
        handler(endDate)
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
        let station = defaults.structData(Station.self, forKey: "closestStation") ??
            Station(name: "-", nameLocal: "-", lon: 119.949875, lat: 26.160469)

        let historyPollutant = HistoryPollutant(
            stationId: 0,
            aqi: 0,
            pm25: 0,
            pm10: 0,
            no2: 0,
            so2: 0,
            co: 0,
            o3: 0,
            publishTime: "--"
        )

        if let template = getDummyTemplate(for: complication, station: station, historyPollutant: historyPollutant) {
            handler(template)
        } else {
            handler(nil)
        }
    }

    private func getDummyTemplate(for complication: CLKComplication, station: Station, historyPollutant: HistoryPollutant) -> CLKComplicationTemplate? {
        let template: CLKComplicationTemplate

        let airStatus = AirStatuses.checkAirStatus(
            airIndexType: AirIndexTypes.aqi,
            value: historyPollutant.aqi
        )
        let airStatusText = "AirStatus.\(airStatus.rawValue)".localized
        let color = UIColor(rgb: Int(airStatus.getColor()))
        let stationName = Locale.isChinese ? station.nameLocal : station.name
        let aqiDisplayValue = historyPollutant.aqi.format(f: AirIndexTypes.aqi.getFormat())
        let pm25DisplayValue = historyPollutant.aqi.format(f: AirIndexTypes.pm25.getFormat())
        let aqiAndPm25 = "AQI \(aqiDisplayValue), PM2.5 \(pm25DisplayValue)"

        switch complication.family {
        case .modularSmall:
            print("complication.family.modularSmall")
            let modularSmallTemplate = CLKComplicationTemplateModularSmallStackText()
            modularSmallTemplate.line1TextProvider = CLKSimpleTextProvider(text: "AQI")
            modularSmallTemplate.line2TextProvider = CLKSimpleTextProvider(text: aqiDisplayValue)
            template = modularSmallTemplate
            template.tintColor = color
            return template
        case .modularLarge:
            print("complication.family.modularLarge")
            let modularLargeTemplate = CLKComplicationTemplateModularLargeStandardBody()
            modularLargeTemplate.headerTextProvider = CLKSimpleTextProvider(text: airStatusText)
            modularLargeTemplate.body1TextProvider = CLKSimpleTextProvider(text: aqiAndPm25)
            modularLargeTemplate.body2TextProvider = CLKSimpleTextProvider(text: stationName)
            template = modularLargeTemplate
            template.tintColor = color
            return template
        case .utilitarianSmall, .utilitarianSmallFlat:
            print("complication.family.utilitarianSmall, .utilitarianSmallFlat")
            let utilitarianSmallTemplate = CLKComplicationTemplateUtilitarianSmallFlat()
            utilitarianSmallTemplate.textProvider = CLKSimpleTextProvider(text: "AQI \(aqiDisplayValue)")
            template = utilitarianSmallTemplate
            template.tintColor = color
            return template
        case .utilitarianLarge:
            print("complication.family.utilitarianLarge")
            let utilitarianLargeTemplate = CLKComplicationTemplateUtilitarianLargeFlat()
            utilitarianLargeTemplate.textProvider = CLKSimpleTextProvider(text: "\(stationName) • \(aqiAndPm25) • \(airStatusText)")
            template = utilitarianLargeTemplate
            template.tintColor = color
            return template
        case .circularSmall:
            print("complication.family.circularSmall")
            let circularSmallTemplate = CLKComplicationTemplateCircularSmallStackText()
            circularSmallTemplate.line1TextProvider = CLKSimpleTextProvider(text: "AQI")
            circularSmallTemplate.line2TextProvider = CLKSimpleTextProvider(text: aqiDisplayValue)
            template = circularSmallTemplate
            template.tintColor = color
            return template
        case .extraLarge:
            print("complication.family.extraLarge")
            let extraLargeTemplate = CLKComplicationTemplateExtraLargeStackText()
            extraLargeTemplate.line1TextProvider = CLKSimpleTextProvider(text: "\(stationName): \(airStatusText)")
            extraLargeTemplate.line2TextProvider = CLKSimpleTextProvider(text: aqiAndPm25)
            template = extraLargeTemplate
            template.tintColor = color
            return template
        case .graphicCorner:
            print("complication.family.graphicCorner")
            let graphicCornerTemplate = CLKComplicationTemplateGraphicCornerStackText()
            graphicCornerTemplate.innerTextProvider = CLKSimpleTextProvider(text: aqiAndPm25)
            graphicCornerTemplate.outerTextProvider = CLKSimpleTextProvider(text: stationName)
            template = graphicCornerTemplate
            template.tintColor = color
            return template
        case .graphicBezel:
            print("complication.family.graphicBezel")
            let gaugeProvider = CLKSimpleGaugeProvider(style: .ring, gaugeColor: color, fillFraction: Float(historyPollutant.aqi / 500))

            let graphicCircularTemplate = CLKComplicationTemplateGraphicCircularOpenGaugeSimpleText()
            graphicCircularTemplate.bottomTextProvider = CLKSimpleTextProvider(text: "AQI")
            graphicCircularTemplate.centerTextProvider = CLKSimpleTextProvider(text: aqiDisplayValue)
            graphicCircularTemplate.gaugeProvider = gaugeProvider

            let graphicBezelTemplate = CLKComplicationTemplateGraphicBezelCircularText()
            graphicBezelTemplate.circularTemplate = graphicCircularTemplate
            template = graphicBezelTemplate
            template.tintColor = color
            return template
        case .graphicCircular:
            print("complication.family.graphicCircular")
            let gaugeProvider = CLKSimpleGaugeProvider(style: .ring, gaugeColor: color, fillFraction: Float(historyPollutant.aqi / 500))

            let template = CLKComplicationTemplateGraphicCircularClosedGaugeText()
            template.centerTextProvider = CLKSimpleTextProvider(text: aqiDisplayValue)
            template.gaugeProvider = gaugeProvider
            return template

        case .graphicRectangular:
            print(".graphicRectangular")
            let graphicRectangularTemplate = CLKComplicationTemplateGraphicRectangularStandardBody()
            graphicRectangularTemplate.headerTextProvider = CLKSimpleTextProvider(text: airStatusText)
            graphicRectangularTemplate.headerTextProvider.tintColor = color
            graphicRectangularTemplate.body1TextProvider = CLKSimpleTextProvider(text: aqiAndPm25)
            graphicRectangularTemplate.body2TextProvider = CLKSimpleTextProvider(text: stationName)
            template = graphicRectangularTemplate
            template.tintColor = .white
            return template
        default:
            return nil
        }
    }

    func reloadData() {
        print("reloadData")
        let server = CLKComplicationServer.sharedInstance()
        guard let complications = server.activeComplications,
            !complications.isEmpty else {
                return
        }

        for complication in complications {
            server.reloadTimeline(for: complication)
        }
    }
}
