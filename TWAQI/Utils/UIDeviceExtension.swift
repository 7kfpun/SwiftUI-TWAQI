//
//  UIDeviceExtension.swift
//  TWAQI
//
//  Created by kf on 10/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import UIKit

extension UIDevice {
    var hasNotch: Bool {
        let bottom = UIApplication.shared.keyWindow?.safeAreaInsets.bottom ?? 0
        return bottom > 0
    }
}
