//
//  IndexSelectorView.swift
//  TWAQI
//
//  Created by kf on 10/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import UIKit

final class IndexSelectorView: UIScrollView {

    var buttons: [UIButton] = []
    var indexButton = UIButton()

    override init(frame: CGRect) {
        super.init(frame: frame)
        createSubviews()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        createSubviews()
    }

    func createSubviews() {
        translatesAutoresizingMaskIntoConstraints = false
        showsHorizontalScrollIndicator = false

        let height: CGFloat = 54

        let buttonPadding: CGFloat = 10
        var xOffset: CGFloat = 15

        for (i, airIndexType) in AirIndexTypes.allCases.enumerated() {
            let button = UIButton()
            buttons.append(button)
            button.tag = i
            button.setTitle(airIndexType.toString(), for: .normal)
            button.setTitleColor(.label, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14)
            button.backgroundColor = .tertiarySystemBackground
            button.layer.cornerRadius = 25
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOffset = CGSize(width: 0, height: 4)
            button.layer.shadowRadius = 2
            button.layer.shadowOpacity = 0.2

            button.frame = CGRect(x: xOffset, y: 0, width: 75, height: 50)
            xOffset += CGFloat(buttonPadding) + button.frame.size.width

            addSubview(button)
        }

        contentSize = CGSize(width: xOffset, height: height)
    }
}
