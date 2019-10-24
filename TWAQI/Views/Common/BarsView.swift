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
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(self.bars) { bar in
                    Capsule()
                        .fill(bar.color)
                        .frame(height: CGFloat(bar.value) / CGFloat(self.max) * geometry.size.height)
                        .overlay(Rectangle().stroke(Color.white))
                }
            }
        }
    }
}

struct BarsView_Previews: PreviewProvider {
    static var previews: some View {
        BarsView(bars: [
            Bar(value: 4, color: Color.green),
            Bar(value: 2, color: Color.green),
            Bar(value: 3, color: Color.green),
            Bar(value: 5, color: Color.green),
            Bar(value: 2, color: Color.green),
            Bar(value: 1, color: Color.green),
            Bar(value: 4, color: Color.green),
        ])
    }
}
