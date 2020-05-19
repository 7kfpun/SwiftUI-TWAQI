//
//  ForecastView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI
import SwiftDate

struct ForecastView: View {
    @ObservedObject var viewModel: ForecastViewModel

    @State var forecastType = 0

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack {
                        Toggle(isOn: $viewModel.isForecastEnabled) {
                            Text("Forecast.forecast_notification_daily")
                                .bold()
                        }
                        .padding(.bottom)

                        Picker(selection: $forecastType, label: Text("Forecast view?")) {
                            Text("Forecast.three_days_forecast").tag(0)
                            Text("Forecast.details_forecast").tag(1)
                        }.pickerStyle(SegmentedPickerStyle())

                        if forecastType == 0 {
                            Forecast3DaysView(forecastAreas: viewModel.forecastAreas)
                        } else if forecastType == 1 {
                            ForecastDetailView(forecastDetail: viewModel.forecastDetail)
                        }
                    }
                    .padding(.horizontal)

                    Spacer().frame(height: 50)
                }

                if !viewModel.isCustomAdLoading {
                    if viewModel.isShowCustomAd {
                        CustomAdView(customAd: viewModel.customAd)
                            .onAppear(perform: submitImpressionEvent)
                    } else {
                        AdBannerView(adUnitID: getEnv("AdUnitIdForecastFooter")!)
                    }
                }
            }
            .navigationBarTitle("Forecast.forecast")
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear(perform: getData)
    }

    private func getData() {
        self.viewModel.getData()
        self.viewModel.getCustomAd()
        Timer.scheduledTimer(withTimeInterval: 60 * 5, repeats: true) { (_) in
            // Schedule in seconds
            self.viewModel.getCustomAd()
        }
    }

    private func submitImpressionEvent() {
        if viewModel.isShowCustomAd {
            if let customAd = viewModel.customAd {
                var components = URLComponents(string: customAd.imageUrl)!
                components.query = nil

                TrackingManager.logEvent(eventName: "ad_custom_impression", parameters: [
                    "name": customAd.name,
                    "position": customAd.position,
                    "impressionRate": customAd.impressionRate,
                    "imageUrl": "\(components.url!)",
                    "destinationUrl": customAd.destinationUrl,
                    "cpc": customAd.cpc,
                ])

                TrackingManager.logEvent(eventName: "ad_custom_\(customAd.name)_impression", parameters: [
                    "name": customAd.name,
                    "position": customAd.position,
                    "impressionRate": customAd.impressionRate,
                    "imageUrl": "\(components.url!)",
                    "destinationUrl": customAd.destinationUrl,
                    "cpc": customAd.cpc,
                ])
            }
        }
    }
}

struct ForecastView_Previews: PreviewProvider {
    static var previews: some View {
        ForecastView(viewModel: .init(
            // swiftlint:disable:next line_length
            forecastDetail: "1.今(15)日受東北風影響，雲嘉南以南位於下風區，擴散條件較差，空氣品質多為普通等級，雲嘉南沿海地區因風速較強，引發地表揚塵現象，局部地區懸浮微粒濃度偏高。依16時監測結果，竹苗、宜蘭空品區為「良好」等級；北部、中部、高屏、花東空品區及馬祖、金門、澎湖地區為「普通」等級為主；雲嘉南空品區多為「橘色提醒」等級。\r2.依氣象局15日16時資料：16日受東北風影響，中部以北擴散條件較佳，北部及東半部有雨；中部以南內陸山區位於弱風區，易累積污染物，午後受光化作用影響易使臭氧濃度上升；雲嘉南沿海地區風速較強，須留意地表揚塵影響空氣品質。竹苗、宜蘭、花東空品區為「良好」等級；北部、中部、高屏空品區及馬祖、金門、澎湖為「普通」等級，中部及高屏空品區局部地區短時間可能達橘色提醒等級；雲嘉南空品區為「橘色提醒」等級，局部地區短時間可能達紅色警示等級。\r3.17日仍為東北風，北部及東半部仍有降雨，擴散條件仍佳；雲嘉南以南位於下風處，污染物易累積，午後受光化作用影響致臭氧濃度上升；雲嘉南地區因沿岸風速較強，仍有機會引發地表揚塵現象影響空氣品質。竹苗、宜蘭及花東空品區為「良好」等級；北部及中部空品區為「普通」等級，中部內陸近山區短時間可能達橘色提醒等級；雲嘉南及高屏空品區為「橘色提醒」等級。\r4.18日持續為東北風，雲嘉南以南位於下風處，污染物仍可能累積，午後受光化作用影響致臭氧濃度上升；雲嘉南地區因沿岸風速較強，仍有機會引發地表揚塵現象。北部、竹苗、宜蘭及花東空品區為「良好」等級；中部空品區為「普通」等級，內陸近山區短時間可能達橘色提醒等級；雲嘉南及高屏空品區為「橘色提醒」等級。未來一週，16日至20日受東北風影響，北部及東半部位於迎風面，擴散條件較佳，雲嘉南以南位於下風處，須留意擴散不良致空氣品質較差；雲嘉南沿海風速較強，須留意地表揚塵現象發生。空氣品質受氣象條件影響大，請隨時留意最新空氣品質資訊，並歡迎下載「環境即時通」APP，依個人防護需求設定不同警戒值通知。\r",
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
        ))
    }
}
