//
//  ClosestStationView.swift
//  TWAQI
//
//  Created by kf on 9/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SnapKit
import UIKit

/// Floating card on the map showing the station nearest the map centre.
///
/// Layout: identity on the left (name, locality, status, last-updated), the
/// current value pill and health face on the right.
final class ClosestStationView: UIView {
    static let preferredSize = CGSize(width: 232, height: 96)

    private var label: UILabel!
    private var localityLabel: UILabel!
    private var subLabel: UILabel!
    private var updatedLabel: UILabel!
    private var aqiLabel: UILabel!
    private var imageView: UIImageView!

    var stationName: String? {
        get { return label?.text }
        set { label.text = newValue?.maxLength(length: 16) }
    }

    /// Township / county, hidden when the API doesn't supply it.
    var locality: String? {
        get { return localityLabel?.text }
        set {
            localityLabel.text = newValue?.maxLength(length: 22)
            localityLabel.isHidden = (newValue?.isEmpty ?? true)
        }
    }

    var status: String? {
        get { return subLabel?.text }
        set { subLabel.text = newValue?.maxLength(length: 20) }
    }

    /// Raw API `publish_time`; rendered as "Updated HH:mm".
    var publishTime: String? {
        didSet { updateUpdatedLabel() }
    }

    /// Set while the map timeline is scrubbed back, e.g. 「昨天 17:00・24 小時前」.
    /// Replaces the clock-only "Updated HH:mm", which reads the same 24 hours
    /// ago as it does now.
    var timelineContext: String? {
        didSet { updateUpdatedLabel() }
    }

    /// The reading is the last good one saved, because the latest request
    /// failed. Says so with its age instead of a bare clock time, which could
    /// be any day this week.
    var isLastGood = false {
        didSet {
            guard isLastGood != oldValue else { return }
            updateUpdatedLabel()
        }
    }

    private func updateUpdatedLabel() {
        if let timelineContext, !timelineContext.isEmpty {
            updatedLabel.isHidden = false
            updatedLabel.text = timelineContext
            updatedLabel.textColor = .label
            return
        }

        if isLastGood, let publishTime, !publishTime.isEmpty {
            updatedLabel.isHidden = false
            updatedLabel.text = String(format: "Offline.updated_ago %@".localized, publishTime.asRelativeAge)
            updatedLabel.textColor = .systemOrange
            return
        }

        updatedLabel.textColor = .secondaryLabel
        guard let publishTime = publishTime, !publishTime.isEmpty else {
            updatedLabel.text = nil
            updatedLabel.isHidden = true
            return
        }
        updatedLabel.isHidden = false
        updatedLabel.text = "\("Details.last_updated".localized) \(publishTime.asPublishTime)"
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
        layer.cornerRadius = 10

        // MARK: Right column — value pill + health face
        let rightView = UIView()
        addSubview(rightView)
        rightView.snp.makeConstraints { (make) -> Void in
            make.top.right.bottom.equalTo(self)
            make.width.equalTo(72)
        }

        aqiLabel = UILabel()
        aqiLabel.font = .systemFont(ofSize: 13, weight: .medium)
        aqiLabel.textAlignment = .center
        aqiLabel.layer.cornerRadius = 6
        aqiLabel.layer.masksToBounds = true
        rightView.addSubview(aqiLabel)
        aqiLabel.snp.makeConstraints { (make) -> Void in
            make.top.equalTo(rightView).offset(12)
            make.centerX.equalTo(rightView)
            make.height.equalTo(24)
            make.width.greaterThanOrEqualTo(56)
        }

        imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        rightView.addSubview(imageView)
        imageView.snp.makeConstraints { (make) -> Void in
            make.top.equalTo(aqiLabel.snp.bottom).offset(8)
            make.centerX.equalTo(rightView)
            make.height.width.equalTo(36)
        }

        // MARK: Left column — identity
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        addSubview(stack)
        stack.snp.makeConstraints { (make) -> Void in
            make.left.equalTo(self).offset(12)
            make.right.equalTo(rightView.snp.left).offset(-4)
            make.centerY.equalTo(self)
        }

        label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        stack.addArrangedSubview(label)

        localityLabel = UILabel()
        localityLabel.font = .systemFont(ofSize: 11, weight: .light)
        localityLabel.textColor = .secondaryLabel
        stack.addArrangedSubview(localityLabel)

        subLabel = UILabel()
        subLabel.font = .systemFont(ofSize: 12)
        subLabel.textColor = .label
        stack.addArrangedSubview(subLabel)

        updatedLabel = UILabel()
        updatedLabel.font = .systemFont(ofSize: 10, weight: .light)
        updatedLabel.textColor = .secondaryLabel
        stack.addArrangedSubview(updatedLabel)
        stack.setCustomSpacing(5, after: subLabel)
    }
}
