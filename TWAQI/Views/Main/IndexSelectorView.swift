//
//  IndexSelectorView.swift
//  TWAQI
//
//  Created by kf on 10/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import UIKit

/// Horizontally scrolling pollutant picker pinned above the map's bottom edge.
///
/// The selected pill is filled with the accent colour rather than merely
/// tinting its title, so the current pollutant reads at a glance over a busy map.
final class IndexSelectorView: UIScrollView {
    static let accent = UIColor(rgb: 0x5AC8FA)
    static let preferredHeight: CGFloat = 54

    var buttons: [UIButton] = []

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

        let buttonPadding: CGFloat = 8
        var xOffset: CGFloat = 15

        for (i, airIndexType) in AirIndexTypes.allCases.enumerated() {
            let button = UIButton()
            buttons.append(button)
            button.tag = i
            button.setTitle(airIndexType.toString(), for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            button.layer.cornerRadius = 21
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOffset = CGSize(width: 0, height: 3)
            button.layer.shadowRadius = 3
            button.layer.shadowOpacity = 0.18

            let width: CGFloat = airIndexType == .aqi ? 62 : 72
            button.frame = CGRect(x: xOffset, y: 6, width: width, height: 42)
            xOffset += buttonPadding + width

            addSubview(button)
        }

        contentSize = CGSize(width: xOffset + 7, height: IndexSelectorView.preferredHeight)
    }

    /// Applies the filled/unfilled treatment across the whole row.
    func setSelected(tag: Int) {
        for button in buttons {
            let isSelected = button.tag == tag
            button.backgroundColor = isSelected ? IndexSelectorView.accent : .tertiarySystemBackground
            button.setTitleColor(isSelected ? .white : .label, for: .normal)
        }
    }
}
