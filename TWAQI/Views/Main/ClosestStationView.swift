//
//  ClosestStationView.swift
//  TWAQI
//
//  Created by kf on 9/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SnapKit
import UIKit

final class ClosestStationView: UIView {
    var label: UILabel!
    var subLabel: UILabel!
    var aqiLabel: UILabel!
    var imageView: UIImageView!

    var stationName: String? {
        get { return label?.text }
        set { label.text = newValue?.maxLength(length: 16) }
    }

    var status: String? {
        get { return subLabel?.text }
        set { subLabel.text = newValue?.maxLength(length: 16) }
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
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 2
        layer.shadowOpacity = 0.2
        layer.cornerRadius = 5

        let leftView = UIView()
        addSubview(leftView)
        leftView.snp.makeConstraints { (make) -> Void in
            make.top.left.bottom.equalTo(self)
            make.width.equalToSuperview().multipliedBy(0.66)
        }

        label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textAlignment = NSTextAlignment.center
        leftView.addSubview(label)
        label.snp.makeConstraints { (make) -> Void in
            make.top.equalTo(leftView).offset(8)
            make.centerX.equalTo(leftView.snp.centerX)
        }

        subLabel = UILabel()
        subLabel.font = UIFont.systemFont(ofSize: 12)
        subLabel.textAlignment = NSTextAlignment.center
        leftView.addSubview(subLabel)
        subLabel.snp.makeConstraints { (make) -> Void in
            make.bottom.equalTo(leftView).offset(-8)
            make.centerX.equalTo(leftView.snp.centerX)
        }

        let rightView = UIView()
        addSubview(rightView)
        rightView.snp.makeConstraints { (make) -> Void in
            make.top.right.bottom.equalTo(self)
            make.width.equalToSuperview().multipliedBy(0.33)
        }

        aqiLabel = UILabel()
        aqiLabel.font = UIFont.systemFont(ofSize: 12)
        aqiLabel.textAlignment = NSTextAlignment.center
        aqiLabel.layer.cornerRadius = 4
        aqiLabel.layer.masksToBounds = true
        rightView.addSubview(aqiLabel)
        aqiLabel.snp.makeConstraints { (make) -> Void in
            make.top.equalTo(rightView).offset(6)
            make.centerX.equalTo(rightView.snp.centerX).offset(-4)
            make.height.equalTo(22)
            make.width.greaterThanOrEqualTo(60)
        }

        imageView = UIImageView(frame: bounds)
        rightView.addSubview(imageView)
        imageView.snp.makeConstraints { (make) -> Void in
            make.bottom.equalTo(rightView).offset(-4)
            make.centerX.equalTo(rightView.snp.centerX).offset(-4)
            make.height.equalTo(34)
            make.width.equalTo(34)
        }
    }
}
