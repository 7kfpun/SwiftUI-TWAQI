//
//  MyLocationButton.swift
//  TWAQI
//
//  Created by kf on 19/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import UIKit

/// The locate-me button. Its icon and VoiceOver value show the mode (FOX-185).
final class MyLocationButton: UIView {
    var button: UIButton!

    var mode: LocateMeMode = .off {
        didSet { updateAppearance() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        createSubviews()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        createSubviews()
    }

    func createSubviews() {
        button = UIButton(frame: CGRect(x: 0, y: 0, width: 60, height: 60))

        button.tintColor = UIColor(rgb: 0x5AC8FA)
        button.backgroundColor = .tertiarySystemBackground
        button.layer.cornerRadius = 30
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        button.layer.shadowRadius = 2
        button.layer.shadowOpacity = 0.2
        button.accessibilityLabel = "Map.Locate.label".localized

        addSubview(button)
        updateAppearance()
    }

    private func updateAppearance() {
        let symbol: String
        let value: String
        let hint: String
        switch mode {
        case .off:
            symbol = "location"
            value = "Map.Locate.off".localized
            hint = "Map.Locate.hint_off".localized
        case .centred:
            symbol = "location.fill"
            value = "Map.Locate.centred".localized
            hint = "Map.Locate.hint_centred".localized
        case .following:
            symbol = "location.north.line.fill"
            value = "Map.Locate.following".localized
            hint = "Map.Locate.hint_following".localized
        }
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.accessibilityValue = value
        button.accessibilityHint = hint
    }
}
