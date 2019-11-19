//
//  FunctionalButtonsView.swift
//  TWAQI
//
//  Created by kf on 10/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SnapKit
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
        // MARK: Default location button
        defaultLocationButton = UIButton()
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
        defaultLocationButton.snp.makeConstraints { (make) -> Void in
            make.top.equalTo(self.snp.top)
            make.height.equalTo(60)
            make.width.equalTo(60)
        }

        // MARK: My location button
        myLocationButton = UIButton()
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
        myLocationButton.snp.makeConstraints { (make) -> Void in
            make.bottom.equalTo(self.snp.bottom)
            make.height.equalTo(60)
            make.width.equalTo(60)
        }
    }
}
