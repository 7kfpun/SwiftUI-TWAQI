//
//  FunctionalButtonsView.swift
//  TWAQI
//
//  Created by kf on 10/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import UIKit

final class FunctionalButtonsView: UIView {
    var defaultLocationButton: UIButton!
    var myLocationButton: UIButton!

    override init(frame: CGRect) {
        super.init(frame: frame)
        createSubviews()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        createSubviews()
    }

    func createSubviews() {
        let width = frame.size.width
        let height = frame.size.height

        // MARK: Default location button
        defaultLocationButton = UIButton(frame: CGRect(
            x: width - 60,
            y: 0,
            width: 60,
            height: 60
        ))
        let defaultLocationIcon = UIImage(systemName: "viewfinder")
        defaultLocationButton.setImage(defaultLocationIcon, for: .normal)
        defaultLocationButton.tintColor = UIColor(rgb: 0x5AC8FA)
        defaultLocationButton.backgroundColor = .tertiarySystemBackground
        defaultLocationButton.layer.cornerRadius = 30
        defaultLocationButton.layer.shadowColor = UIColor.black.cgColor
        defaultLocationButton.layer.shadowOffset = CGSize(width: 0.0, height: 3.0)
        defaultLocationButton.layer.shadowRadius = 2
        defaultLocationButton.layer.shadowOpacity = 0.1
        addSubview(defaultLocationButton)

        // MARK: My location button
        myLocationButton = UIButton(frame: CGRect(
            x: width - 60,
            y: height - 60,
            width: 60,
            height: 60
        ))
        let myLocationIcon = UIImage(systemName: "paperplane.fill")
        myLocationButton.setImage(myLocationIcon, for: .normal)
        myLocationButton.tintColor = UIColor(rgb: 0x5AC8FA)
        myLocationButton.backgroundColor = .tertiarySystemBackground
        myLocationButton.layer.cornerRadius = 30
        myLocationButton.layer.shadowColor = UIColor.black.cgColor
        myLocationButton.layer.shadowOffset = CGSize(width: 0.0, height: 3.0)
        myLocationButton.layer.shadowRadius = 2
        myLocationButton.layer.shadowOpacity = 0.1
        addSubview(myLocationButton)
    }
}
