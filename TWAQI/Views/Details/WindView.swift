//
//  WindView.swift
//  TWAQI
//
//  Created by kf on 8/8/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// Which way the air is moving, and how hard.
///
/// Split out of the old combined "conditions" block, which ran wind and the
/// station's street address together under one heading — one is a live
/// measurement, the other is fixed metadata, and reading them as a single
/// section made neither obvious.
struct WindView: View {
    var wind: Wind

    /// Band colour of whichever pollutant the page is currently showing.
    ///
    /// Follows the selection, as the map's wind arrows do, so the arrow matches
    /// the highlighted reading and the chart above it.
    var tint: Color = Color(0x5AC8FA)

    @State private var drifting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Details.wind")

            HStack(spacing: 20) {
                compass
                readings
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal)
    }

    /// A compass rose rather than a bare arrow in a ring. An arrow on its own
    /// has no frame of reference — without a fixed north mark, its angle is
    /// decoration, and "WSW" doesn't tell you which way that points.
    private var compass: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)

            ForEach([0, 90, 180, 270], id: \.self) { degrees in
                Capsule()
                    .fill(Color.secondary.opacity(degrees == 0 ? 0.55 : 0.22))
                    .frame(width: 1.5, height: degrees == 0 ? 8 : 5)
                    .offset(y: -30)
                    .rotationEffect(.degrees(Double(degrees)))
            }

            Text(verbatim: "N")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .offset(y: -40)

            if wind.isCalm {
                Text(verbatim: "—")
                    .font(.title3)
                    .foregroundColor(.secondary)
            } else {
                arrow
            }
        }
        .frame(width: 72, height: 72)
    }

    /// The arrow points the way the air is travelling, and its length is the
    /// speed — a light air is a stub, a strong breeze nearly spans the rose.
    /// It drifts along its own axis, faster in stronger wind, so direction
    /// reads without having to work out which end is the head.
    private var arrow: some View {
        WindArrow(length: arrowLength)
            .stroke(
                tint,
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )
            .frame(width: 72, height: 72)
            // Wavers around the bearing rather than sliding along it — a vane
            // in real wind hunts either side of the true direction, and a
            // sliding arrow read as the whole dial drifting off-centre.
            .rotationEffect(wind.arrowRotation + .degrees(drifting ? wobble : -wobble))
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: driftDuration).repeatForever(autoreverses: true),
                value: drifting
            )
            .onAppear { drifting = true }
    }

    private var arrowLength: CGFloat {
        // Floor and ceiling: below the floor a light air would vanish, above it
        // a strong breeze would overrun the compass ring.
        let shortest: CGFloat = 18
        let longest: CGFloat = 46
        return shortest + (longest - shortest) * CGFloat(wind.strengthFraction)
    }

    /// Stronger wind wavers faster.
    private var driftDuration: Double {
        1.5 - 0.9 * wind.strengthFraction
    }

    /// Half the sweep, in degrees. Kept small: past a few degrees the arrow
    /// stops reading as "roughly WSW" and starts looking like it can't decide.
    private var wobble: Double {
        3 + 4 * wind.strengthFraction
    }

    private var readings: some View {
        VStack(alignment: .leading, spacing: 3) {
            if wind.isCalm {
                Text("Wind.calm")
                    .font(.title3)
                    .fontWeight(.medium)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(wind.speed.format(f: ".1"))
                        .font(.title2)
                        .fontWeight(.medium)

                    Text(verbatim: "m/s")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(verbatim: wind.compassPoint)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }

                Text(wind.toString())
                    .font(.footnote)
                    .fontWeight(.light)
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// A shaft with a chevron head, pointing down (south) at rest so that rotating
/// it by the meteorological bearing leaves it pointing where the air is going.
///
/// A drawn shape rather than an SF Symbol because the length has to vary with
/// speed, and a symbol can only scale in both dimensions at once.
private struct WindArrow: Shape {
    var length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.midX
        let top = rect.midY - length / 2
        let tip = rect.midY + length / 2
        let head = min(11, length * 0.5)
        let halfWidth = min(7, length * 0.32)

        path.move(to: CGPoint(x: x, y: top))
        path.addLine(to: CGPoint(x: x, y: tip))

        path.move(to: CGPoint(x: x - halfWidth, y: tip - head))
        path.addLine(to: CGPoint(x: x, y: tip))
        path.addLine(to: CGPoint(x: x + halfWidth, y: tip - head))

        return path
    }
}

struct WindView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            WindView(wind: Wind(direction: 247, speed: 2.6))
            WindView(wind: Wind(direction: 120, speed: 1.4), tint: .orange)
            WindView(wind: Wind(direction: 30, speed: 9.0), tint: .red)
            WindView(wind: Wind(direction: 0, speed: 0))
        }
        .previewLayout(.sizeThatFits)
    }
}
