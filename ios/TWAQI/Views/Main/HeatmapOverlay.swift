//
//  HeatmapOverlay.swift
//  TWAQI
//
//  TWAQ-22: the optional heatmap layer. One ground overlay under the markers;
//  the image is computed off the main thread and cached until the readings or
//  the palette change, so panning and zooming only touch the overlay's opacity.
//

import GoogleMaps
import UIKit

final class HeatmapOverlay {
    /// Taiwan with its outlying islands, plus a margin for the reach.
    static let bounds = HeatmapBounds(south: 21.6, west: 117.9, north: 26.5, east: 122.3)
    private static let width = 300
    private static let height = 340

    private weak var mapView: GMSMapView?
    private var overlay: GMSGroundOverlay?
    private let queue = DispatchQueue(label: "heatmap.render", qos: .userInitiated)
    /// Identifies the inputs of the image on screen; a repeat call with the
    /// same key does no work.
    private var renderedKey: Int?
    private var generation = 0
    private var zoom: Float = 7

    var isEnabled = false {
        didSet {
            if !isEnabled { overlay?.map = nil } else if overlay != nil { overlay?.map = mapView }
        }
    }

    init(mapView: GMSMapView) {
        self.mapView = mapView
    }

    /// Rebuilds the image when `samples` or `palette` differ from the last
    /// call. `color` maps a value to `0xRRGGBB`.
    func update(samples: [HeatmapSample], paletteKey: Int, color: @escaping (Double) -> UInt32) {
        var hasher = Hasher()
        hasher.combine(paletteKey)
        for sample in HeatmapInterpolation.usable(samples) {
            hasher.combine(sample.latitude)
            hasher.combine(sample.longitude)
            hasher.combine(sample.value)
        }
        let key = hasher.finalize()
        guard key != renderedKey else { return }
        renderedKey = key
        generation += 1
        let wanted = generation
        queue.async { [weak self] in
            let width = Self.width, height = Self.height
            let cells = HeatmapInterpolation.grid(samples: samples, bounds: Self.bounds, width: width, height: height)
            let image = HeatmapInterpolation.image(cells: cells, width: width, height: height, color: color)
            DispatchQueue.main.async {
                guard let self, wanted == self.generation, let image else { return }
                self.show(UIImage(cgImage: image))
            }
        }
    }

    func zoomChanged(_ zoom: Float) {
        self.zoom = zoom
        overlay?.opacity = HeatmapInterpolation.opacity(forZoom: zoom)
    }

    private func show(_ image: UIImage) {
        let b = Self.bounds
        let box = GMSCoordinateBounds(
            coordinate: CLLocationCoordinate2D(latitude: b.south, longitude: b.west),
            coordinate: CLLocationCoordinate2D(latitude: b.north, longitude: b.east)
        )
        let overlay = self.overlay ?? GMSGroundOverlay(bounds: box, icon: image)
        overlay.icon = image
        overlay.bounds = box
        overlay.opacity = HeatmapInterpolation.opacity(forZoom: zoom)
        // Under every marker, over the base map.
        overlay.zIndex = -20
        overlay.isTappable = false
        overlay.map = isEnabled ? mapView : nil
        self.overlay = overlay
    }
}

/// Where the heatmap's on/off choice is remembered.
enum HeatmapLayer {
    static let defaultsKey = "heatmapLayerOn"
}

/// Toggle for the heatmap layer (TWAQ-22), beside the wind layer button.
final class HeatmapLayerButton: UIView {
    var button: UIButton!

    var isOn: Bool {
        get { return button.tintColor == .white }
        set {
            button.tintColor = newValue ? .white : .label
            button.backgroundColor = newValue ? UIColor(rgb: 0xFF9500) : .tertiarySystemBackground
            button.accessibilityValue = (newValue ? "Map.Heatmap.on" : "Map.Heatmap.off").localized
            button.isSelected = newValue
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        createSubviews()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        createSubviews()
    }

    private func createSubviews() {
        button = UIButton(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        button.setImage(UIImage(systemName: "smoke.fill"), for: .normal)
        button.layer.cornerRadius = 30
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        button.layer.shadowRadius = 2
        button.layer.shadowOpacity = 0.2
        button.accessibilityLabel = "Map.Heatmap.label".localized
        button.accessibilityHint = "Map.Heatmap.hint".localized
        addSubview(button)
        isOn = false
    }
}

/// "Estimated between stations", shown while the layer is on.
final class HeatmapNoteLabel: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        text = "  " + "Map.Heatmap.estimated".localized + "  "
        font = .preferredFont(forTextStyle: .caption1)
        adjustsFontForContentSizeCategory = true
        textColor = .label
        backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85)
        layer.cornerRadius = 10
        clipsToBounds = true
        isHidden = true
        accessibilityLabel = "Map.Heatmap.description".localized
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
