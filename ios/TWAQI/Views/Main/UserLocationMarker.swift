//
//  UserLocationMarker.swift
//  TWAQI
//
//  FOX-185: the "you are here" dot, drawn here: a blue dot with a white ring,
//  a pulse, and a heading cone when the compass has a heading.
//
//  Copyright © 2026 kf. All rights reserved.
//

import UIKit

final class UserLocationMarkerView: UIView {
    static let size: CGFloat = 64

    private let pulse = CALayer()
    private let cone = CAShapeLayer()
    private let ring = CALayer()
    private let dot = CALayer()
    private let blue = UIColor(rgb: 0x007AFF)

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.size, height: Self.size))
        isUserInteractionEnabled = false
        let center = CGPoint(x: Self.size / 2, y: Self.size / 2)

        pulse.bounds = CGRect(x: 0, y: 0, width: 22, height: 22)
        pulse.position = center
        pulse.cornerRadius = 11
        pulse.backgroundColor = blue.withAlphaComponent(0.35).cgColor
        layer.addSublayer(pulse)

        // Points up; the marker is flat, so the map rotates it to the heading.
        let path = UIBezierPath()
        path.move(to: center)
        path.addArc(withCenter: center, radius: 30, startAngle: -.pi / 2 - .pi / 5, endAngle: -.pi / 2 + .pi / 5, clockwise: true)
        path.close()
        cone.path = path.cgPath
        cone.fillColor = blue.withAlphaComponent(0.45).cgColor
        cone.isHidden = true
        layer.addSublayer(cone)

        ring.bounds = CGRect(x: 0, y: 0, width: 22, height: 22)
        ring.position = center
        ring.cornerRadius = 11
        ring.backgroundColor = UIColor.white.cgColor
        ring.shadowColor = UIColor.black.cgColor
        ring.shadowOpacity = 0.35
        ring.shadowRadius = 3
        ring.shadowOffset = CGSize(width: 0, height: 1)
        layer.addSublayer(ring)

        dot.bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
        dot.position = center
        dot.cornerRadius = 8
        dot.backgroundColor = blue.cgColor
        layer.addSublayer(dot)

        NotificationCenter.default.addObserver(
            self, selector: #selector(motionPreferenceChanged),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil
        )
        startPulse()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var showsHeading: Bool {
        get { !cone.isHidden }
        set { cone.isHidden = !newValue }
    }

    @objc private func motionPreferenceChanged() { startPulse() }

    /// Called when the marker joins a window; a pulse is removed when the app
    /// goes to the background, so it starts again.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { startPulse() }
    }

    /// With Reduce Motion on, the pulse stays as a still halo.
    private func startPulse() {
        pulse.removeAllAnimations()
        guard !UIAccessibility.isReduceMotionEnabled else {
            pulse.transform = CATransform3DMakeScale(1.6, 1.6, 1)
            pulse.opacity = 0.6
            return
        }
        pulse.transform = CATransform3DIdentity
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 2.6
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.8
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 1.8
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pulse.add(group, forKey: "pulse")
    }
}
