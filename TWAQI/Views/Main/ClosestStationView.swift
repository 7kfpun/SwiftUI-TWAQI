//
//  ClosestStationView.swift
//  TWAQI
//
//  Created by kf on 9/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import UIKit

final class ClosestStationView: UIView {
    var label: UILabel!
    var subLabel: UILabel!
    var aqiLabel: UILabel!
    var imageView: UIImageView!

    var stationName: String? {
        get { return label?.text }
        set { label.text = newValue }
    }

    var status: String? {
        get { return subLabel?.text }
        set { subLabel.text = newValue }
    }

    var aqi: String? {
        get { return aqiLabel?.text }
        set { aqiLabel.text = newValue }
    }

    var aqiColor: UIColor? {
        get { return aqiLabel?.backgroundColor }
        set { aqiLabel.backgroundColor = newValue }
    }

    var aqiForegroundColor: UIColor? {
        get { return aqiLabel?.textColor }
        set { aqiLabel.textColor = newValue }
    }

    var image: UIImage? {
        get { return imageView.image }
        set { imageView.image = newValue }
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        createSubviews()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        createSubviews()
    }

    func createSubviews() {
        translatesAutoresizingMaskIntoConstraints = false

        backgroundColor = .tertiarySystemBackground
        layer.cornerRadius = 5

        let width = frame.size.width

        label = UILabel(frame: CGRect(origin: CGPoint(x: 0, y: 8), size: CGSize(width: width * 2 / 3, height: 20)))
        label.font = UIFont.systemFont(ofSize: 12)
        label.textAlignment = NSTextAlignment.center
        addSubview(label)

        subLabel = UILabel(frame: CGRect(origin: CGPoint(x: 0, y: 50), size: CGSize(width: width * 2 / 3, height: 20)))
        subLabel.font = UIFont.systemFont(ofSize: 12)
        subLabel.textAlignment = NSTextAlignment.center
        addSubview(subLabel)

        aqiLabel = UILabel(frame: CGRect(origin: CGPoint(x: width * 2 / 3, y: 6), size: CGSize(width: width / 3 - 12, height: 20)))
        aqiLabel.font = UIFont.systemFont(ofSize: 12)
        aqiLabel.textAlignment = NSTextAlignment.center
        aqiLabel.layer.cornerRadius = 4
        aqiLabel.layer.masksToBounds = true
        addSubview(aqiLabel)

        imageView = UIImageView(frame: bounds)
        imageView.frame = CGRect(x: width * 2 / 3 + 13, y: 36, width: 34, height: 34)
        addSubview(imageView)
    }
}
