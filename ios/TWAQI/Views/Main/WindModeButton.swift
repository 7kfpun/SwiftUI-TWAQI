//
//  WindModeButton.swift
//  TWAQI
//
//  Created by kf on 11/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI
import UIKit

final class WindModeButton: UIView {
    var button: UIButton!

    var isWindMode: Bool {
        get { return button.tintColor == .white }
        set {
            button.tintColor = newValue ? .white : .label
            button.backgroundColor = newValue ? UIColor(rgb: 0x5AC8FA) : .tertiarySystemBackground
        }
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
        // MARK: Wind button
        button = UIButton(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        let windModeIcon = UIImage(systemName: "wind")
        button.setImage(windModeIcon, for: .normal)
        button.layer.cornerRadius = 30
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        button.layer.shadowRadius = 2
        button.layer.shadowOpacity = 0.2

        addSubview(button)
    }
}

/// Toggle for the wind arrows layer (TWAQ-15), above the wind-mode button.
final class WindLayerButton: UIView {
    var button: UIButton!

    var isOn: Bool {
        get { return button.tintColor == .white }
        set {
            button.tintColor = newValue ? .white : .label
            button.backgroundColor = newValue ? UIColor(rgb: 0x0A84FF) : .tertiarySystemBackground
            button.accessibilityValue = (newValue ? "Map.WindLayer.on" : "Map.WindLayer.off").localized
            button.isSelected = newValue
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        createSubviews()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        createSubviews()
    }

    private func createSubviews() {
        button = UIButton(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        button.setImage(UIImage(systemName: "location.north.line"), for: .normal)
        button.layer.cornerRadius = 30
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        button.layer.shadowRadius = 2
        button.layer.shadowOpacity = 0.2
        button.accessibilityLabel = "Map.WindLayer.label".localized
        button.accessibilityHint = "Map.WindLayer.hint".localized
        addSubview(button)
        isOn = false
    }
}
