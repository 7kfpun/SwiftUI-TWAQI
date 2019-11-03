//
//  ProgressView.swift
//  TWAQI
//
//  Created by kf on 23/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct Bar: Identifiable {
    let id = UUID()
    let value: Double
    let color: Color
}

struct BarsView: View {
    let bars: [Bar]
    let max: Double

    init(bars: [Bar]) {
        self.bars = bars
        self.max = bars.map { $0.value }.max() ?? 0
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(self.bars) { bar in
                    VStack {
                        Spacer()
                        Capsule()
                            .fill(bar.color)
                            .frame(height: self.max > 0 ? CGFloat(bar.value) / CGFloat(self.max) * geometry.size.height : 1)
                    }
                }
            }
        }
    }
}

struct BarsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            BarsView(bars: [
                Bar(value: 2, color: Color.green),
                Bar(value: 1, color: Color.green),
                Bar(value: 4, color: Color.green),
                Bar(value: 2, color: Color.green),
                Bar(value: 3, color: Color.green),
                Bar(value: 1, color: Color.green),
                Bar(value: 2, color: Color.green),
                Bar(value: 1, color: Color.green),
                Bar(value: 4, color: Color.green),
                Bar(value: 2, color: Color.green),
                Bar(value: 3, color: Color.green),
                Bar(value: 1, color: Color.green),
                Bar(value: 2, color: Color.green),
                Bar(value: 1, color: Color.green),
                Bar(value: 5, color: Color.green),
                Bar(value: 2, color: Color.green),
                Bar(value: 1, color: Color.green),
                Bar(value: 4, color: Color.green),
            ])

            BarsView(bars: [
                Bar(value: 0, color: Color.green),
                Bar(value: 0, color: Color.green),
                Bar(value: 0, color: Color.green),
                Bar(value: 0, color: Color.green),
                Bar(value: 0, color: Color.green),
                Bar(value: 0, color: Color.green),
                Bar(value: 0, color: Color.green),
                Bar(value: 0, color: Color.green),
                Bar(value: 0, color: Color.green),
                Bar(value: 0, color: Color.green),
                Bar(value: 0, color: Color.green),
                Bar(value: 0, color: Color.green),
                Bar(value: 0, color: Color.green),
                Bar(value: 0, color: Color.green),
                Bar(value: 0, color: Color.green),
                Bar(value: 0, color: Color.green),
                Bar(value: 0, color: Color.green),
                Bar(value: 0, color: Color.green),
            ])
        }
        .previewLayout(.fixed(width: 500, height: 200))
        .environment(\.colorScheme, .dark)
    }
}
