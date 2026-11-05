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
