//
//  FavouriteRow.swift
//  TWAQI
//
//  Created by kf on 4/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct FavouriteRow: View {
    var pollutant: Pollutant

    var body: some View {
        let airStatus = AirStatuses.checkAirStatus(
            airIndexType: AirIndexTypes.aqi,
            value: Double(self.pollutant.aqi)
        )

        return NavigationLink(destination: DetailsView(stationId: pollutant.stationId).environmentObject(SettingsStore())) {
            VStack {
                HStack {
                    Text(Locale.isChinese ? self.pollutant.nameLocal : self.pollutant.name)
                        .foregroundColor(Color.primary)
                        .padding(.top, 10)
                        .padding(.horizontal, 12)
                    Spacer()
                }

                Divider()

                HStack {
                    VStack(alignment: .leading) {
                        GeometryReader { geometry in
                            HStack {
                                VStack {
                                    Text("AQI \(Int(self.pollutant.aqi))")
                                        .font(.callout)
                                        .fontWeight(.regular)
                                        .padding(.vertical, 3)
                                        .padding(.horizontal, 10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(Color.primary, lineWidth: 0.5)
                                        )

                                    Spacer()

                                    Image("status_\(airStatus)")
                                        .resizable()
                                        .frame(width: 65, height: 65)
                                        .padding(.top, 10)

                                    Spacer()

                                    Text(airStatus.toString())
                                        .foregroundColor(Color(airStatus.getForegroundColor()))
                                        .font(.footnote)
                                        .fontWeight(.regular)
                                        .multilineTextAlignment(.center)
                                        .padding(.vertical, 3)
                                        .padding(.horizontal)
                                        .lineLimit(2)
                                        .background(Color(airStatus.getColor()))
                                        .cornerRadius(6)
                                }
                                .frame(width: geometry.size.width / 3)

                                VStack(alignment: .leading) {
                                    Text("Details.general_public")
                                        .font(.callout)
                                        .fontWeight(.regular)
                                        .padding(.vertical, 3)
                                        .padding(.horizontal, 10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(Color.primary, lineWidth: 0.5)
                                        )

                                    Text(airStatus.getGeneralPublicGuidance())
                                        .font(.footnote)
                                        .fontWeight(.thin)
                                        .padding(.top, 6)

                                    Spacer()

                                    Text("Details.sensitive_group")
                                        .font(.callout)
                                        .fontWeight(.regular)
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(Color.primary, lineWidth: 0.5)
                                        )

                                    Text(airStatus.getSensitivePublicGuidance())
                                        .font(.footnote)
                                        .fontWeight(.thin)
                                        .padding(.top, 6)
                                }
                                .frame(width: geometry.size.width * 2 / 3)
                            }
                        }
                        .frame(height: 160)
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundColor(Color.secondary)
                        .padding(.horizontal)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary, lineWidth: 0.5)
            )
            .padding(.horizontal)
            .padding(.bottom, 5)
            .shadow(radius: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

//struct FavouriteRow_Previews: PreviewProvider {
//    static var previews: some View {
//        Group {
//            FavouriteRow()
//            FavouriteRow()
//            FavouriteRow()
//        }
//        .previewLayout(.fixed(width: 400, height: 250))
//    }
//}
