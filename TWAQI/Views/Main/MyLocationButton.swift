//
//  MyLocationButton.swift
//  TWAQI
//
//  Created by kf on 19/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import UIKit

final class MyLocationButton: UIView {
    var button: UIButton!

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

        let icon = UIImage(systemName: "paperplane.fill")
        button.setImage(icon, for: .normal)
        button.tintColor = UIColor(rgb: 0x5AC8FA)
        button.backgroundColor = .tertiarySystemBackground
        button.layer.cornerRadius = 30
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        button.layer.shadowRadius = 2
        button.layer.shadowOpacity = 0.2

        addSubview(button)
    }
}
