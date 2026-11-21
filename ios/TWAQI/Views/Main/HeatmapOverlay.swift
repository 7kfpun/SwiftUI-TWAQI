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
        overlay.zIndex = -10
        overlay.isTappable = false
        overlay.map = isEnabled ? mapView : nil
        self.overlay = overlay
    }
}
