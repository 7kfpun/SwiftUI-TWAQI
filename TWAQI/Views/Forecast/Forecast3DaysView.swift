//
//  Forecast3DaysView.swift
//  TWAQI
//
//  Created by kf on 27/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct Forecast3DaysView: View {
    var forecastAreas: ForecastAreas

    var body: some View {
        let groupedByAreas = Dictionary(grouping: forecastAreas) { $0.area }

        return VStack {
            Indicator()
                .frame(height: 90)

            HStack {
                Text("Forecast.publish_time")
                Spacer()
                Text(forecastAreas.first?.publishTime ?? "")
            }

            HStack {
                Spacer()
                ForEach(groupedByAreas["北部"] ?? [], id: \.self) {area in
                    HStack {
                        Text(area.forecastDate.toDate("yyyy-MM-dd")?.toFormat("MM/dd") ?? "")
                            .fontWeight(.regular)
                    }
                    .frame(width: 70)
                }
            }
            .padding(.vertical, 10)

            ForEach(AreaGroups.allCases, id: \.self) {areaGroup in
                HStack {
                    Text(areaGroup.toString())
                    Spacer()
                    ForEach(groupedByAreas[areaGroup.getKey()] ?? [], id: \.self) {area in
                        HStack {
                            LabelView(
                                airIndexTypes: AirIndexTypes.aqi,
                                value: Double((area as ForecastArea).aqi) ?? 0
                            )
                        }
                        .frame(width: 70)
                    }
                }
            }
            .padding(.vertical, 10)
        }
    }
}

struct Forecast3DaysView_Previews: PreviewProvider {
    static var previews: some View {
        Forecast3DaysView(
            forecastAreas: [
                ForecastArea(
                    aqi: "55",
                    area: "北部",
                    content: "Content",
                    forecastDate: "2019-10-16",
                    majorPollutant: "細懸浮微粒",
                    minorPollutant: "",
                    minorPollutantAQI: "",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "55",
                    area: "北部",
                    content: "Content",
                    forecastDate: "2019-10-17",
                    majorPollutant: "細懸浮微粒",
                    minorPollutant: "",
                    minorPollutantAQI: "",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "50",
                    area: "北部",
                    content: "Content",
                    forecastDate: "2019-10-18",
                    majorPollutant: "",
                    minorPollutant: "",
                    minorPollutantAQI: "",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "50",
                    area: "竹苗",
                    content: "Content",
                    forecastDate: "2019-10-16",
                    majorPollutant: "",
                    minorPollutant: "",
                    minorPollutantAQI: "",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "50",
                    area: "竹苗",
                    content: "Content",
                    forecastDate: "2019-10-17",
                    majorPollutant: "",
                    minorPollutant: "",
                    minorPollutantAQI: "",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "50",
                    area: "竹苗",
                    content: "Content",
                    forecastDate: "2019-10-18",
                    majorPollutant: "",
                    minorPollutant: "",
                    minorPollutantAQI: "",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "100",
                    area: "中部",
                    content: "Content",
                    forecastDate: "2019-10-16",
                    majorPollutant: "臭氧八小時",
                    minorPollutant: "",
                    minorPollutantAQI: "",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "100",
                    area: "中部",
                    content: "Content",
                    forecastDate: "2019-10-17",
                    majorPollutant: "臭氧八小時",
                    minorPollutant: "",
                    minorPollutantAQI: "",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "100",
                    area: "中部",
                    content: "Content",
                    forecastDate: "2019-10-18",
                    majorPollutant: "臭氧八小時",
                    minorPollutant: "",
                    minorPollutantAQI: "",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "140",
                    area: "雲嘉南",
                    content: "Content",
                    forecastDate: "2019-10-16",
                    majorPollutant: "懸浮微粒",
                    minorPollutant: "臭氧八小時",
                    minorPollutantAQI: "105",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "120",
                    area: "雲嘉南",
                    content: "Content",
                    forecastDate: "2019-10-17",
                    majorPollutant: "懸浮微粒",
                    minorPollutant: "臭氧八小時",
                    minorPollutantAQI: "105",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "110",
                    area: "雲嘉南",
                    content: "Content",
                    forecastDate: "2019-10-18",
                    majorPollutant: "懸浮微粒",
                    minorPollutant: "臭氧八小時",
                    minorPollutantAQI: "105",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "105",
                    area: "高屏",
                    content: "Content",
                    forecastDate: "2019-10-16",
                    majorPollutant: "臭氧八小時",
                    minorPollutant: "",
                    minorPollutantAQI: "",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "110",
                    area: "高屏",
                    content: "Content",
                    forecastDate: "2019-10-17",
                    majorPollutant: "臭氧八小時",
                    minorPollutant: "細懸浮微粒",
                    minorPollutantAQI: "105",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "115",
                    area: "高屏",
                    content: "Content",
                    forecastDate: "2019-10-18",
                    majorPollutant: "臭氧八小時",
                    minorPollutant: "細懸浮微粒",
                    minorPollutantAQI: "110",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "50",
                    area: "宜蘭",
                    content: "Content",
                    forecastDate: "2019-10-16",
                    majorPollutant: "",
                    minorPollutant: "",
                    minorPollutantAQI: "",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "50",
                    area: "宜蘭",
                    content: "Content",
                    forecastDate: "2019-10-17",
                    majorPollutant: "",
                    minorPollutant: "",
                    minorPollutantAQI: "",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "50",
                    area: "宜蘭",
                    content: "Content",
                    forecastDate: "2019-10-18",
                    majorPollutant: "",
                    minorPollutant: "",
                    minorPollutantAQI: "",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "50",
                    area: "花東",
                    content: "Content",
                    forecastDate: "2019-10-16",
                    majorPollutant: "",
                    minorPollutant: "",
                    minorPollutantAQI: "",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "50",
                    area: "花東",
                    content: "Content",
                    forecastDate: "2019-10-17",
                    majorPollutant: "",
                    minorPollutant: "",
                    minorPollutantAQI: "",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "50",
                    area: "花東",
                    content: "Content",
                    forecastDate: "2019-10-18",
                    majorPollutant: "",
                    minorPollutant: "",
                    minorPollutantAQI: "",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "60",
                    area: "馬祖",
                    content: "Content",
                    forecastDate: "2019-10-16",
                    majorPollutant: "細懸浮微粒",
                    minorPollutant: "",
                    minorPollutantAQI: "",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "70",
                    area: "金門",
                    content: "Content",
                    forecastDate: "2019-10-16",
                    majorPollutant: "細懸浮微粒",
                    minorPollutant: "",
                    minorPollutantAQI: "",
                    publishTime: "2019-10-15 22:00"
                ),
                ForecastArea(
                    aqi: "55",
                    area: "澎湖",
                    content: "Content",
                    forecastDate: "2019-10-16",
                    majorPollutant: "臭氧八小時",
                    minorPollutant: "",
                    minorPollutantAQI: "",
                    publishTime: "2019-10-15 22:00"
                ),
            ]
        )
        .previewLayout(.sizeThatFits)
    }
}
