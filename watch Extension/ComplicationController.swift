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

    let settingsStore = SettingsStore()

    // MARK: - Timeline Configuration
    func getSupportedTimeTravelDirections(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimeTravelDirections) -> Void) {
        handler([.forward, .backward])
    }
    
    func getPrivacyBehavior(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void) {
        handler(.showOnLockScreen)
    }

    func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {
        // Call the handler with the current timeline entry
        let station = settingsStore.closestStation
        let airIndexTypeSelected = settingsStore.airIndexTypeSelected

        APIManager.getHistoricalPollutants(stationId: station.id) { result in
            switch result {
            case .success(let result):
                let historicalPollutants = result["data"] as! HistoricalPollutants

                if let latestHistoricalPollutant = historicalPollutants.last {
                    self.settingsStore.latestHistoricalPollutant = latestHistoricalPollutant

                    if let template = self.getDummyTemplate(
                        for: complication,
                        station: station,
                        historicalPollutant: latestHistoricalPollutant,
                        airIndexTypeSelected: airIndexTypeSelected
                    ) {
                        let entry = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template)
                        handler(entry)
                    } else {
                        handler(nil)
                    }
                }
            case .failure(let error):
                print(error.localizedDescription)
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
        let station = settingsStore.closestStation
        let historicalPollutant = settingsStore.latestHistoricalPollutant

        if let template = getDummyTemplate(
            for: complication, station: station, historicalPollutant: historicalPollutant, airIndexTypeSelected: AirIndexTypes.aqi
        ) {
            handler(template)
        } else {
            handler(nil)
        }
    }

    func getDummyTemplate(for complication: CLKComplication, station: Station, historicalPollutant: HistoricalPollutant, airIndexTypeSelected: AirIndexTypes) -> CLKComplicationTemplate? {
        let template: CLKComplicationTemplate

        let stationName = Locale.isChinese ? station.nameLocal : station.name
        let aqiDisplayValue = historicalPollutant.aqi.format(f: AirIndexTypes.aqi.getFormat())
        let pm25DisplayValue = historicalPollutant.pm25.format(f: AirIndexTypes.pm25.getFormat())
        let aqiAndPm25 = "\(AirIndexTypes.aqi.toString()) \(aqiDisplayValue), \(AirIndexTypes.pm25.toString()) \(pm25DisplayValue)"

        var airStatus: AirStatuses
        var displayValue: String
        var displayFraction: Float
        if airIndexTypeSelected == AirIndexTypes.aqi {
            airStatus = AirStatuses.checkAirStatus(
                airIndexType: AirIndexTypes.aqi,
                value: historicalPollutant.aqi
            )
            displayValue = aqiDisplayValue
            displayFraction = Float(historicalPollutant.aqi / 500)
        } else {
            airStatus = AirStatuses.checkAirStatus(
                airIndexType: AirIndexTypes.pm25,
                value: historicalPollutant.pm25
            )
            displayValue = pm25DisplayValue
            displayFraction = Float(historicalPollutant.pm25 / 500)
        }

        let airStatusText = "AirStatus.\(airStatus.rawValue)".localized
        let color = UIColor(rgb: Int(airStatus.getColor()))

        switch complication.family {
        case .modularSmall:
            print("complication.family.modularSmall")
            let modularSmallTemplate = CLKComplicationTemplateModularSmallStackText()
            modularSmallTemplate.line1TextProvider = CLKSimpleTextProvider(text: airIndexTypeSelected.toString())
            modularSmallTemplate.line2TextProvider = CLKSimpleTextProvider(text: displayValue)
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
            utilitarianSmallTemplate.textProvider = CLKSimpleTextProvider(text: "\(airIndexTypeSelected.toString()) \(displayValue)")
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
            circularSmallTemplate.line1TextProvider = CLKSimpleTextProvider(text: airIndexTypeSelected.toString())
            circularSmallTemplate.line2TextProvider = CLKSimpleTextProvider(text: displayValue)
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
            let gaugeProvider = CLKSimpleGaugeProvider(style: .ring, gaugeColor: color, fillFraction: displayFraction)

            let graphicCircularTemplate = CLKComplicationTemplateGraphicCircularOpenGaugeSimpleText()
            graphicCircularTemplate.bottomTextProvider = CLKSimpleTextProvider(text: airIndexTypeSelected.toString())
            graphicCircularTemplate.centerTextProvider = CLKSimpleTextProvider(text: displayValue)
            graphicCircularTemplate.gaugeProvider = gaugeProvider

            let graphicBezelTemplate = CLKComplicationTemplateGraphicBezelCircularText()
            graphicBezelTemplate.circularTemplate = graphicCircularTemplate
            template = graphicBezelTemplate
            template.tintColor = color
            return template
        case .graphicCircular:
            print("complication.family.graphicCircular")
            let gaugeProvider = CLKSimpleGaugeProvider(style: .ring, gaugeColor: color, fillFraction: displayFraction)

            let template = CLKComplicationTemplateGraphicCircularClosedGaugeText()
            template.centerTextProvider = CLKSimpleTextProvider(text: displayValue)
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
}
