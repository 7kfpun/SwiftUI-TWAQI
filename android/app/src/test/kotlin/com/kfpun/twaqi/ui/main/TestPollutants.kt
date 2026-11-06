package com.kfpun.twaqi.ui.main

import com.kfpun.twaqi.data.model.Pollutant

/** A reading with only what the map and list look at. */
fun pollutant(
    id: Int,
    lat: Double = 25.0,
    lon: Double = 121.5,
    aqi: Double = 50.0,
    name: String = "Station $id",
    nameLocal: String = "測站$id",
    county: String? = null,
    countyLocal: String? = null,
    township: String? = null,
    pm25: Double = 10.0
) = Pollutant(
    stationId = id,
    code = "s$id",
    lat = lat,
    lon = lon,
    aqi = aqi,
    pm25 = pm25,
    pm10 = 20.0,
    no2 = 5.0,
    so2 = 1.0,
    co = 0.3,
    o3 = 30.0,
    windDirection = 0.0,
    windSpeed = 0.0,
    publishTime = "2026-11-06 14:00:00",
    name = name,
    nameLocal = nameLocal,
    county = county,
    countyLocal = countyLocal,
    township = township
)
