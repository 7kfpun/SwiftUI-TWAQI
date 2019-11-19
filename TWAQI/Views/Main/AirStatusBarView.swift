//
//  AirStatusBarView.swift
//  TWAQI
//
//  Created by kf on 9/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import UIKit

final class AirStatusBarView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        createSubviews()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        createSubviews()
    }

    func createSubviews() {
        backgroundColor = .tertiarySystemBackground
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 2
        layer.shadowOpacity = 0.1
        layer.cornerRadius = 5

        let width: CGFloat = 200
        let imagePadding: CGFloat = (width - 10) / 6 - 20
        var xOffset: CGFloat = 10

        for airStatus in AirStatuses.getShowAllCases() {
            let faceImage = UIImage(named: "status_\(airStatus)")
            let faceImageView = UIImageView(image: faceImage)
            faceImageView.frame = CGRect(x: xOffset, y: 5, width: 20, height: 20)

            let bar = UIView(frame: CGRect(x: xOffset, y: 26, width: 20, height: 3))
            bar.backgroundColor = UIColor(rgb: Int(airStatus.getColor()))
            bar.layer.cornerRadius = 2
            bar.layer.borderColor = UIColor.white.cgColor
            bar.layer.borderWidth = 0.2

            xOffset += CGFloat(imagePadding) + faceImageView.frame.size.width

            addSubview(faceImageView)
            addSubview(bar)
        }
    }
}
