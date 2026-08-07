//
//  HealthGuidanceView.swift
//  TWAQI
//
//  Created by kf on 8/8/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// What this air quality means for you: advice for the general public and for
/// sensitive groups.
///
/// Advice only. It used to carry its own AQI number, face and status chip in a
/// left-hand third, which on the station screen repeated the header verbatim —
/// the same reading, face and status appeared twice within one scroll.
struct HealthGuidanceView: View {
    var aqi: Double

    var body: some View {
        let status = AirStatuses.checkAirStatus(airIndexType: .aqi, value: aqi)

        return VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Details.health_advice")

            advice(
                title: "Details.general_public",
                body: status.getGeneralPublicGuidance(),
                status: status
            )

            advice(
                title: "Details.sensitive_group",
                body: status.getSensitivePublicGuidance(),
                status: status
            )
        }
        .padding(.horizontal)
    }

    private func advice(
        title: LocalizedStringKey,
        body: LocalizedStringKey,
        status: AirStatuses
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // A colour rule rather than a boxed chip — it ties the advice to the
            // current band without competing with the header's status pill.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(status.getColor()))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(body)
                    .font(.footnote)
                    .fontWeight(.light)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct HealthGuidanceView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            HealthGuidanceView(aqi: 20)
            HealthGuidanceView(aqi: 141)
            HealthGuidanceView(aqi: 0)
        }
        .previewLayout(.sizeThatFits)
    }
}
