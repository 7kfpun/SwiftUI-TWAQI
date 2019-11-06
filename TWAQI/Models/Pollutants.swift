//
//  Pollutants.swift
//  TWAQI
//
//  Created by kf on 2/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

typealias Pollutants = [Pollutant]

struct Pollutant: Codable {
    let aqi: String
    let co: String
    let co8hr: String
    let county: String
    let latitude: String
    let longitude: String
    let no: String
    let no2: String
    let nox: String
    let o3: String
    let o38hr: String
    let pm10: String
    let pm10Avg: String
    let pm25: String
    let pm25Avg: String
    let pollutant: String
    let publishTime: String
    let so2: String
    let so2Avg: String
    let siteId: String
    let siteName: String
    let status: String
    let windDirection: String
    let windSpeed: String

    private enum CodingKeys: String, CodingKey {
        case aqi = "AQI"
        case co = "CO"
        case co8hr = "CO_8hr"
        case county = "County"
        case latitude = "Latitude"
        case longitude = "Longitude"
        case no = "NO"
        case no2 = "NO2"
        case nox = "NOx"
        case o3 = "O3"
        case o38hr = "O3_8hr"
        case pm10 = "PM10"
        case pm10Avg = "PM10_AVG"
        case pm25 = "PM2_5"
        case pm25Avg = "PM2_5_AVG"
        case pollutant = "Pollutant"
        case publishTime = "PublishTime"
        case so2 = "SO2"
        case so2Avg = "SO2_AVG"
        case siteId = "SiteId"
        case siteName = "SiteName"
        case status = "Status"
        case windDirection = "WindDirec"
        case windSpeed = "WindSpeed"
    }

    func getValue(airIndexType: AirIndexTypes) -> Double {
        switch airIndexType {
        case AirIndexTypes.aqi:
            return Double(self.aqi) ?? 0
        case AirIndexTypes.pm25:
            return Double(self.pm25) ?? 0
        case AirIndexTypes.pm10:
            return Double(self.pm10) ?? 0
        case AirIndexTypes.no2:
            return Double(self.no2) ?? 0
        case AirIndexTypes.so2:
            return Double(self.so2) ?? 0
        case AirIndexTypes.co:
            return Double(self.co) ?? 0
        case AirIndexTypes.o3:
            return Double(self.o3) ?? 0
        }
    }

    func getStation() -> Station {
        return Station(
            name: self.siteName,
            nameLocal: self.siteName,
            lon: Double(self.longitude) ?? 0,
            lat: Double(self.latitude) ?? 0
        )
    }
}
