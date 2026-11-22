//
//  GoogleMapController.swift
//  TWAQI
//
//  Created by kf on 2/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import CoreLocation
import GoogleMaps
import SnapKit
import SwiftUI
import UIKit

let defaults = UserDefaults.standard

class GoogleMapViewController: UIViewController, GMSMapViewDelegate {
    /// The camera the user last left the map at, or `MapHome` on first launch.
    ///
    /// Evaluated per instance rather than once at process start, so a camera
    /// saved during this session is honoured if the controller is rebuilt.
    static var initialCamera: GMSCameraPosition {
        let settings = SettingsStore()
        let hasSavedPosition = !(settings.lastestMapLat == 0 && settings.lastestMapLon == 0)

        return GMSCameraPosition.camera(
            withLatitude: hasSavedPosition ? settings.lastestMapLat : MapHome.latitude,
            longitude: hasSavedPosition ? settings.lastestMapLon : MapHome.longitude,
            zoom: settings.lastestMapZoom > 0 ? settings.lastestMapZoom : MapHome.zoom
        )
    }

    let mapView: GMSMapView = {
        let options = GMSMapViewOptions()
        options.camera = GoogleMapViewController.initialCamera
        return GMSMapView(options: options)
    }()

    var closestStationView: ClosestStationView!
    var defaultLocationButton: DefaultLocationButton!
    var indexSelectorView: IndexSelectorView!
    var myLocationButton: MyLocationButton!

    // Locate me (FOX-185)
    let locationTracker = UserLocationTracker()
    private let userMarkerView = UserLocationMarkerView()
    private var userMarker: GMSMarker?
    private var userHalo: GMSCircle?
    private var pendingLocateTap = false
    private var pendingCentre = false
    var locateMode: LocateMeMode = .off {
        didSet { myLocationButton?.mode = locateMode }
    }
    var timelineView: MapTimelineView!
    var windModeButton: WindModeButton!
    var windLayerButton: WindLayerButton!
    var heatmapButton: HeatmapLayerButton!
    private let heatmapNote = HeatmapNoteLabel()
    private lazy var heatmapOverlay = HeatmapOverlay(mapView: mapView)

    /// The timeline bar sits above the ad banner, which SwiftUI lays out
    /// outside this map, with the index bar on top of it. Kept so both can drop
    /// down when the banner goes away.
    private var bottomBarBottom: Constraint?
    private var proObserver: NSObjectProtocol?
    private var onboardingObserver: NSObjectProtocol?
    private var hasBannerLayout = false
    private var consentObserver: AnyCancellable?

    /// Gap between the index bar and the tab bar, plus the banner when shown.
    private static func bannerClearance(hasBanner: Bool) -> CGFloat {
        hasBanner ? -(AdBannerView.height + 10) : -10
    }

    /// A banner is on screen only for free users UMP lets ask for ads.
    private var hasBanner: Bool {
        AdBannerView.reservesSpace(isPro: defaults.bool(forKey: "pro"), canRequestAds: ConsentManager.shared.canRequestAds)
    }

    var currentLatitude: Double = GoogleMapViewController.initialCamera.target.latitude
    var currentLongitude: Double = GoogleMapViewController.initialCamera.target.longitude

    var countries: Countries = []
    var closestCountry: Country!

    /// Code of the country whose markers are openable. Resolved from the
    /// countries endpoint so the id -> code mapping stays server-driven.
    var supportedCountryCode: String? {
        didSet { if closestStationView != nil { loadClosestStationView() } }
    }

    var pollutants: Pollutants = []

    /// A tapped station. `MainView` opens it in the panel beside the map or
    /// in a sheet over it, whichever the window's width calls for.
    var onStationSelected: ((Int) -> Void)?

    /// Station open in the panel beside the map, if any. Kept in view when
    /// the panel opens, or the window resizes, and takes width from the map.
    var panelStationId: Int?
    private var lastLayoutWidth: CGFloat = 0

    deinit {
        // A closed iPad window must free its map: stop the refresh timer and
        // drop every observer this controller registered (FOX-135).
        refreshTimer?.invalidate()
        locationTracker.stop()
        [proObserver, foregroundObserver, backgroundObserver]
            .forEach { $0.map(NotificationCenter.default.removeObserver) }
    }

    @objc func toggleIsWindMode() {
        self.isWindMode = !self.isWindMode
        TrackingManager.logEvent(.setWindMode, parameters: ["label": self.isWindMode ? "on" : "off"])
    }

    @objc func toggleWindLayer() {
        windLayerOn.toggle()
    }

    /// The button's action. `goToMyLocation(isSkipLog:)` can't be the
    /// selector itself: UIKit would pass the button as `isSkipLog`, which
    /// then read as an arbitrary Bool and dropped the event at random.
    @objc private func myLocationTapped() {
        goToMyLocation()
    }

    // MARK: - Locate me (FOX-185)

    /// Tap: ask on first use, explain when denied, otherwise step the mode.
    func goToMyLocation(isSkipLog: Bool = false) {
        switch locationTracker.access {
        case .ask:
            pendingLocateTap = true
            locationTracker.requestAccess()
        case .explain:
            showLocationOffAlert()
        case .allowed:
            locationTracker.startIfAllowed()
            locateMode = locateMode.afterTap
            if !isSkipLog { TrackingManager.logEvent(.moveToCurrentLocation) }
            if let location = locationTracker.location {
                centreOnUser(location, zoomToStation: locateMode == .centred)
            } else {
                // First fix still on its way: the next update centres.
                pendingCentre = true
            }
        }
    }

    private func handleAccessChange(_ access: LocateMeAccess) {
        if access == .allowed, pendingLocateTap {
            pendingLocateTap = false
            goToMyLocation()
        } else if access != .ask {
            pendingLocateTap = false
        }
        if access != .allowed { clearUserMarker(); locateMode = .off }
    }

    private func handleLocation(_ location: CLLocation) {
        updateUserMarker(location)
        if pendingCentre {
            pendingCentre = false
            centreOnUser(location, zoomToStation: true)
        } else if locateMode == .following {
            mapView.animate(toLocation: location.coordinate)
        }
    }

    private func centreOnUser(_ location: CLLocation, zoomToStation: Bool) {
        currentLatitude = location.coordinate.latitude
        currentLongitude = location.coordinate.longitude
        let zoom: Float
        if zoomToStation {
            let stations = countryPollutants.values.flatMap { $0 }
                .map { (id: $0.stationId, latitude: $0.lat, longitude: $0.lon) }
            let nearest = LocateMe.nearest(to: location.coordinate, in: stations)
            zoom = LocateMe.zoom(latitude: location.coordinate.latitude, nearestStationDistance: nearest?.distance)
        } else {
            zoom = max(mapView.camera.zoom, LocateMe.minZoom)
        }
        mapView.animate(to: GMSCameraPosition.camera(withTarget: location.coordinate, zoom: zoom))
        updateUserMarker(location)
    }

    /// Camera moves the app makes itself report `gesture == false`. A user gesture on the map ends centring and following.
    func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
        guard gesture, locateMode != .off else { return }
        pendingCentre = false
        locateMode = locateMode.afterGesture
    }

    private func updateUserMarker(_ location: CLLocation) {
        if userMarker == nil {
            let marker = GMSMarker()
            marker.iconView = userMarkerView
            marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
            marker.isFlat = true
            marker.isTappable = false
            marker.zIndex = 1_000
            marker.title = "Map.Locate.you_are_here".localized
            userMarker = marker
        }
        userMarker?.position = location.coordinate
        userMarker?.map = mapView

        if let radius = LocateMe.haloRadius(horizontalAccuracy: location.horizontalAccuracy) {
            if userHalo == nil {
                let halo = GMSCircle()
                halo.fillColor = UIColor(rgb: 0x007AFF).withAlphaComponent(0.15)
                halo.strokeColor = UIColor(rgb: 0x007AFF).withAlphaComponent(0.5)
                halo.strokeWidth = 1
                halo.zIndex = 999
                userHalo = halo
            }
            userHalo?.position = location.coordinate
            userHalo?.radius = radius
            userHalo?.map = mapView
        } else {
            userHalo?.map = nil
        }
    }

    private func clearUserMarker() {
        userMarker?.map = nil
        userHalo?.map = nil
    }

    private func syncHeadingOrientation() {
        if let orientation = view.window?.windowScene?.interfaceOrientation {
            locationTracker.setInterfaceOrientation(orientation)
        }
    }

    private func handleHeading(_ heading: CLLocationDirection?) {
        userMarkerView.showsHeading = heading != nil
        userMarker?.rotation = heading ?? 0
    }

    private func showLocationOffAlert() {
        let alert = UIAlertController(
            title: "Map.Locate.off_title".localized,
            message: "Map.Locate.off_message".localized,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Map.Locate.cancel".localized, style: .cancel))
        alert.addAction(UIAlertAction(title: "Map.Locate.open_settings".localized, style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        present(alert, animated: true)
    }

    @objc func goToDefaultLocation() {
        // Always the supported country, not whichever happens to be nearest.
        let supported = countries.first { $0.isSupported && $0.hasValidLocation }
        let zoom = supported.map { $0.zoom > 0 ? $0.zoom : MapHome.zoom } ?? MapHome.zoom

        let defaultCamera = GMSCameraPosition.camera(
            withLatitude: supported?.lat ?? MapHome.latitude,
            longitude: supported?.lon ?? MapHome.longitude,
            zoom: zoom
        )
        self.mapView.animate(to: defaultCamera)
        TrackingManager.logEvent(.moveToDefaultLocation)
    }

    @objc func changeIndex(sender: UIButton?) {
        if let tag = sender?.tag {
            let airIndexTypes = AirIndexTypes.allCases[tag]
            self.airIndexTypeSelected = airIndexTypes

            indexSelectorView.setSelected(tag: tag)

            TrackingManager.logEvent(.selectIndex, parameters: ["label": airIndexTypes.rawValue])
        }
    }

    var isWindMode = false {
        didSet {
            windModeButton.isWindMode = isWindMode
            loadMarkers()
        }
    }

    /// The wind arrows layer (TWAQ-15): off until turned on, then remembered.
    var windLayerOn = defaults.bool(forKey: WindLayer.defaultsKey) {
        didSet {
            guard windLayerOn != oldValue else { return }
            defaults.set(windLayerOn, forKey: WindLayer.defaultsKey)
            windLayerButton?.isOn = windLayerOn
            TrackingManager.logEvent(.setWindLayer, parameters: ["label": windLayerOn ? "on" : "off"])
            refreshWindLayer()
            scheduleCenterWeather()
        }
    }

    /// The heatmap layer (TWAQ-22): off until turned on, then remembered.
    var heatmapOn = defaults.bool(forKey: HeatmapLayer.defaultsKey) {
        didSet {
            guard heatmapOn != oldValue else { return }
            defaults.set(heatmapOn, forKey: HeatmapLayer.defaultsKey)
            heatmapButton?.isOn = heatmapOn
            TrackingManager.logEvent(.setHeatmapLayer, parameters: ["label": heatmapOn ? "on" : "off"])
            refreshHeatmap()
        }
    }

    @objc func toggleHeatmap() {
        heatmapOn.toggle()
    }

    /// Stations with a reading at the timeline's hour feed the estimate; the
    /// image is rebuilt off the main thread only when they or the palette
    /// change (`HeatmapOverlay` skips identical input).
    func refreshHeatmap() {
        heatmapOverlay.isEnabled = heatmapOn
        heatmapNote.isHidden = !heatmapOn
        guard heatmapOn else { return }
        let type = airIndexTypeSelected
        let palette = AQIPalette.current
        var samples: [HeatmapSample] = []
        for pollutants in countryPollutants.values {
            let hour = timelineHour(anchor: Self.anchor(of: pollutants))
            for live in pollutants {
                let (pollutant, hasData) = displayedPollutant(live, hour: hour)
                guard hasData else { continue }
                samples.append(HeatmapSample(latitude: pollutant.lat, longitude: pollutant.lon, value: pollutant.getValue(airIndexType: type)))
            }
        }
        var hasher = Hasher()
        hasher.combine(type.rawValue)
        hasher.combine(palette.rawValue)
        heatmapOverlay.update(samples: samples, paletteKey: hasher.finalize()) { value in
            AirStatuses.checkAirStatus(airIndexType: type, value: value).getColor(palette: palette)
        }
        heatmapOverlay.zoomChanged(mapView.camera.zoom)
    }

    /// Fresh CWA wind readings, strongest first; empty until the layer is on
    /// and the weather file has loaded.
    private var windReadings: [WindReading] = []
    private var windMarkers: [String: WindArrowMarker] = [:]

    /// Reloads the readings (the store answers from its cache within its
    /// ttl) and redraws. Off, or scrubbed back in time (wind is the current
    /// reading only), clears the arrows.
    func refreshWindLayer() {
        guard windLayerOn, timelineHoursAgo == 0 else {
            windReadings = []
            renderWindArrows()
            return
        }
        StationWeatherStore.shared.weather { [weak self] file in
            guard let self = self, self.windLayerOn, self.timelineHoursAgo == 0 else { return }
            self.windReadings = file.map { WindLayer.readings(in: $0) } ?? []
            self.renderWindArrows()
        }
    }

    /// Draws the readings in view, thinned by zoom (`WindLayer.visible`).
    /// Markers are kept and only added or removed as the view moves, so a
    /// pan costs a handful of changes, not a rebuild.
    func renderWindArrows() {
        let wanted: [WindReading]
        if windReadings.isEmpty {
            wanted = []
        } else {
            let region = mapView.projection.visibleRegion()
            let corners = [region.nearLeft, region.nearRight, region.farLeft, region.farRight]
            wanted = WindLayer.visible(
                windReadings,
                minLat: corners.map(\.latitude).min() ?? 0, maxLat: corners.map(\.latitude).max() ?? 0,
                minLon: corners.map(\.longitude).min() ?? 0, maxLon: corners.map(\.longitude).max() ?? 0,
                zoom: Double(mapView.camera.zoom)
            )
        }
        let ids = Set(wanted.map(\.stationId))
        for (id, marker) in windMarkers where !ids.contains(id) {
            marker.map = nil
            windMarkers[id] = nil
        }
        for reading in wanted {
            if let marker = windMarkers[reading.stationId] {
                if marker.reading != reading { marker.update(reading) }
            } else {
                let marker = WindArrowMarker(reading: reading)
                marker.map = mapView
                windMarkers[reading.stationId] = marker
            }
        }
    }

    var airIndexTypeSelected: AirIndexTypes {
        get {
            return defaults.string(forKey: "airIndexTypeSelected")
                .flatMap { AirIndexTypes(rawValue: $0) } ?? .aqi
        }

        set {
            defaults.set(newValue.rawValue, forKey: "airIndexTypeSelected")
            loadClosestStationView()
            loadMarkers()
        }
    }

    var countryPollutants: [String: Pollutants] = [:] {
        didSet {
            closestStationView?.isLoading = false
            loadMarkers()
            updateTimelineAnchor()
            // A new publish hour moves the window; top up what's in view.
            if timelineHoursAgo > 0 {
                requestVisibleHistory()
            }
            // New readings change the PM2.5 behind the hint; the weather
            // store answers from its cache within its ttl.
            scheduleCenterWeather()
            refreshWindLayer()
        }
    }

    // MARK: Timeline

    let historyStore = MapHistoryStore()

    /// Hours before the latest reading the map is showing. 0 is live, and
    /// draws exactly what it did before the timeline existed.
    var timelineHoursAgo = 0 {
        didSet {
            guard timelineHoursAgo != oldValue else { return }
            timelineView.hoursAgo = timelineHoursAgo
            // Markers and the card only. `checkClosestStation` would also
            // republish to the widgets, which must keep the live reading.
            renderMarkers()
            loadClosestStationView()
            updateCenterWeather()
            refreshWindLayer()
        }
    }

    private var playTimer: Timer?

    var closestPollutant: Pollutant! {
        didSet {
            loadClosestStationView()
        }
    }

    func callGetCountriesApi() {
        APIManager.getCountries { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let result):
                self.countries = result

                if let supported = result.first(where: { $0.isSupported }) {
                    self.supportedCountryCode = supported.code
                    // The search tab lists stations for this country rather than
                    // whichever country the map happens to be panned over.
                    defaults.set(supported.code, forKey: "supportedCountryCode")
                    self.callGetCurrentPollutantsApi(countryCode: supported.code)
                } else {
                    // Online, but no supported country to load readings for:
                    // the card is not waiting on anything, and no error either.
                    self.closestStationView.isLoading = false
                }

                self.checkClosestCountry(latitude: self.currentLatitude, longitude: self.currentLongitude)
                self.loadMarkers()
            case .failure(let error):
                AppLog.network.error("getCountries failed: \(error.localizedDescription)")
                // Offline launch: the country list is only needed to know
                // which country to load, and the last answer is saved. Its
                // pollutants request falls back to the last good readings.
                // The list itself is asked for again on the next foreground.
                if self.supportedCountryCode == nil,
                   let code = defaults.string(forKey: "supportedCountryCode"), !code.isEmpty {
                    self.supportedCountryCode = code
                    self.callGetCurrentPollutantsApi(countryCode: code)
                } else if self.closestPollutant == nil {
                    // First launch offline: no country known, nothing saved.
                    self.closestStationView.showUnavailable()
                }
            }
        }
    }

    /// Country codes with a `getCurrentPollutants` request already on the wire.
    ///
    /// `countryPollutants` only records responses that have *arrived*, so it
    /// cannot stop a second request going out while the first is still in
    /// flight. That response is ~65KB and takes over a second, and
    /// `mapView(_:idleAt:)` fires repeatedly while the camera settles — launch
    /// was sending this same request four times.
    private var pollutantRequestsInFlight: Set<String> = []

    /// Countries whose markers are the last good readings from disk (or from
    /// earlier this session) because the latest request failed. Their card
    /// says so, and they are never published to the widgets, which may have
    /// fetched something newer themselves.
    private var lastGoodCountryCodes: Set<String> = [] {
        didSet {
            guard lastGoodCountryCodes != oldValue else { return }
            loadClosestStationView()
        }
    }

    private var foregroundObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    /// The 15-minute data refresh. Held weakly by the run loop's target
    /// (the block captures `self` weakly) and invalidated in `deinit`.
    private(set) var refreshTimer: Timer?
    /// When the paused timer was due, kept across a background trip.
    private var pausedFireDate: Date?

    func callGetCurrentPollutantsApi(countryCode: String) {
        guard !pollutantRequestsInFlight.contains(countryCode) else { return }
        pollutantRequestsInFlight.insert(countryCode)

        APIManager.getCurrentPollutants(countryCode: countryCode) { [weak self] result in
            guard let self = self else { return }
            self.pollutantRequestsInFlight.remove(countryCode)

            switch result {
            case .success(let result):
                self.lastGoodCountryCodes.remove(countryCode)
                self.countryPollutants[countryCode] = result
                WidgetBridge.publish(
                    pollutants: self.liveCountryPollutants,
                    closest: self.liveClosestPollutant
                )
            case .failure(let error):
                AppLog.network.error("getCurrentPollutants failed: \(error.localizedDescription)")
                // Keep what is on screen; with nothing on screen yet, show the
                // last good readings rather than an empty map.
                if self.countryPollutants[countryCode] == nil {
                    guard let cached = PollutantCache.shared.pollutants(countryCode: countryCode) else {
                        if self.closestPollutant == nil { self.closestStationView.showUnavailable() }
                        return
                    }
                    self.lastGoodCountryCodes.insert(countryCode)
                    self.countryPollutants[countryCode] = cached
                } else {
                    self.lastGoodCountryCodes.insert(countryCode)
                }
            }
        }
    }

    /// Pollutants from countries whose latest request succeeded.
    private var liveCountryPollutants: Pollutants {
        countryPollutants
            .filter { !lastGoodCountryCodes.contains($0.key) }
            .values
            .flatMap { $0 }
    }

    /// The closest station, unless its reading is a last good one.
    private var liveClosestPollutant: Pollutant? {
        closestPollutant.flatMap { isLastGood(stationId: $0.stationId) ? nil : $0 }
    }

    private func isLastGood(stationId: Int) -> Bool {
        countryPollutants.contains { countryCode, pollutants in
            lastGoodCountryCodes.contains(countryCode) && pollutants.contains { $0.stationId == stationId }
        }
    }

    /// Back from the background, possibly back online: retry what failed.
    /// The 15-minute timer alone left an offline launch on old readings for
    /// up to a quarter of an hour after the connection returned.
    private func refreshAfterForeground() {
        if countries.isEmpty {
            callGetCountriesApi()
        }
        for countryCode in lastGoodCountryCodes {
            callGetCurrentPollutantsApi(countryCode: countryCode)
        }
    }

    func checkClosestCountry(latitude: Double, longitude: Double) {
        // Placeholder rows (no name, 0/0 coordinates) would otherwise win the
        // nearest search for anywhere near the Gulf of Guinea.
        let locatableCountries = self.countries.filter { $0.hasValidLocation }

        if !locatableCountries.isEmpty {
            var closestCountry: Country = locatableCountries.first!
            var distance: Double = .greatestFiniteMagnitude
            locatableCountries.forEach { country in
                let countryLat = country.lat
                let countryLon = country.lon

                let tempDistance = pow(countryLat - latitude, 2) + pow(countryLon - longitude, 2)
                if tempDistance < distance {
                    closestCountry = country
                    distance = tempDistance
                }
            }

            self.closestCountry = closestCountry
            defaults.set(closestCountry.code, forKey: "closestCountryCode")

            let keyExists = self.countryPollutants[closestCountry.code] != nil

            if !keyExists {
                callGetCurrentPollutantsApi(countryCode: closestCountry.code)
            }
        }
    }

    /// Built once. Everything is pinned to the view, so the map follows the
    /// window as it rotates, folds or unfolds, splits, or makes room for the
    /// station panel beside it, rather than being rebuilt from the screen size
    /// (which is not the window size in split screen).
    func loadContent() {
        let view = UIView()
        view.backgroundColor = .white
        mapView.frame = view.bounds
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(mapView)

        // MARK: closestStationView
        closestStationView = ClosestStationView()
        closestStationView.isLoading = true
        closestStationView.onAdviceChange = { [weak self] in self?.updateClosestStationHeight() }
        view.addSubview(closestStationView)
        closestStationView.snp.makeConstraints { (make) -> Void in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(8)
            make.left.equalTo(view.safeAreaLayoutGuide.snp.left).offset(15)
            make.width.equalTo(ClosestStationView.preferredSize.width)
            closestStationHeight = make.height.equalTo(ClosestStationView.preferredSize.height).constraint
        }

        closestStationView.addTarget(self, action: #selector(closestStationTapped), for: .touchUpInside)

        // MARK: airStatusesView
        let airStatusesView = AirStatusBarView()
        view.addSubview(airStatusesView)
        airStatusesView.snp.makeConstraints { (make) -> Void in
            make.top.equalTo(closestStationView.snp.bottom).offset(8)
            make.left.equalTo(view.safeAreaLayoutGuide.snp.left).offset(15)
            make.width.equalTo(ClosestStationView.preferredSize.width)
            make.height.equalTo(32)
        }

        let hasBanner = self.hasBanner
        hasBannerLayout = hasBanner
        let airIndexTypeSelected = defaults.string(forKey: "airIndexTypeSelected")
            .flatMap { AirIndexTypes(rawValue: $0) } ?? .aqi

        // MARK: Timeline
        timelineView = MapTimelineView()
        timelineView.onInteractionBegan = { [weak self] in
            guard let self else { return }
            self.stopPlaying()
            self.requestVisibleHistory()
        }
        timelineView.onChange = { [weak self] hoursAgo in
            self?.timelineHoursAgo = hoursAgo
        }
        timelineView.onPlayTapped = { [weak self] in
            self?.togglePlay()
        }
        historyStore.onChange = { [weak self] in
            self?.historyDidChange()
        }
        view.addSubview(timelineView)
        timelineView.snp.makeConstraints { (make) -> Void in
            bottomBarBottom = make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
                .offset(Self.bannerClearance(hasBanner: hasBanner)).constraint
            make.height.equalTo(MapTimelineView.preferredHeight)
            make.centerX.equalTo(view.safeAreaLayoutGuide.snp.centerX)
            make.width.lessThanOrEqualTo(view.safeAreaLayoutGuide.snp.width).offset(-30)
            make.width.equalTo(560).priority(.high)
        }

        // MARK: Index Selector
        indexSelectorView = IndexSelectorView()
        for (i, airIndexType) in AirIndexTypes.allCases.enumerated() {
            indexSelectorView.buttons[i].addTarget(self, action: #selector(changeIndex), for: .touchUpInside)

            if airIndexTypeSelected == airIndexType {
                indexSelectorView.setSelected(tag: i)
            }
        }
        view.addSubview(indexSelectorView)
        indexSelectorView.snp.makeConstraints { (make) -> Void in
            make.bottom.equalTo(timelineView.snp.top)
            make.height.equalTo(IndexSelectorView.preferredHeight)
            // Centred at its natural width when there is room, otherwise the
            // full width and scrolling.
            make.centerX.equalTo(view.safeAreaLayoutGuide.snp.centerX)
            make.width.lessThanOrEqualTo(view.safeAreaLayoutGuide.snp.width)
            make.width.equalTo(indexSelectorView.contentSize.width).priority(.high)
        }

        // MARK: My Location Button
        myLocationButton = MyLocationButton()
        view.addSubview(myLocationButton)
        myLocationButton.snp.makeConstraints { (make) -> Void in
            make.bottom.equalTo(indexSelectorView.snp.top).offset(-12)
            make.right.equalTo(view.safeAreaLayoutGuide.snp.right).offset(-15)
            make.width.equalTo(60)
            make.height.equalTo(60)
        }
        myLocationButton.button.addTarget(self, action: #selector(myLocationTapped), for: .touchUpInside)

        // MARK: Default Location Button
        defaultLocationButton = DefaultLocationButton()
        view.addSubview(defaultLocationButton)
        defaultLocationButton.snp.makeConstraints { (make) -> Void in
            make.bottom.equalTo(myLocationButton.snp.top).offset(-12)
            make.right.equalTo(view.safeAreaLayoutGuide.snp.right).offset(-15)
            make.width.equalTo(60)
            make.height.equalTo(60)
        }
        defaultLocationButton.button.addTarget(self, action: #selector(goToDefaultLocation), for: .touchUpInside)

        // MARK: Wind button
        windModeButton = WindModeButton()
        windModeButton.isWindMode = false
        windModeButton.button.addTarget(self, action: #selector(toggleIsWindMode), for: .touchUpInside)
        view.addSubview(windModeButton)
        windModeButton.snp.makeConstraints { (make) -> Void in
            make.bottom.equalTo(indexSelectorView.snp.top).offset(-12)
            make.left.equalTo(view.safeAreaLayoutGuide.snp.left).offset(15)
            make.width.equalTo(60)
            make.height.equalTo(60)
        }

        // MARK: Wind layer button
        windLayerButton = WindLayerButton()
        windLayerButton.isOn = windLayerOn
        windLayerButton.button.addTarget(self, action: #selector(toggleWindLayer), for: .touchUpInside)
        view.addSubview(windLayerButton)
        windLayerButton.snp.makeConstraints { (make) -> Void in
            // Same row as the wind-mode button, so the left stack stays one
            // button tall and clears the station card in landscape.
            make.bottom.equalTo(windModeButton)
            make.left.equalTo(windModeButton.snp.right).offset(12)
            make.width.equalTo(60)
            make.height.equalTo(60)
        }

        // MARK: Heatmap layer button
        heatmapButton = HeatmapLayerButton()
        heatmapButton.isOn = heatmapOn
        heatmapButton.button.addTarget(self, action: #selector(toggleHeatmap), for: .touchUpInside)
        view.addSubview(heatmapButton)
        heatmapButton.snp.makeConstraints { (make) -> Void in
            make.bottom.equalTo(windModeButton)
            make.left.equalTo(windLayerButton.snp.right).offset(12)
            make.width.equalTo(60)
            make.height.equalTo(60)
        }
        view.addSubview(heatmapNote)
        // Trails the colour legend, not the button row: the row stays one
        // button tall so it clears the station card in landscape.
        heatmapNote.snp.makeConstraints { (make) -> Void in
            make.left.equalTo(airStatusesView.snp.right).offset(8)
            make.centerY.equalTo(airStatusesView)
            make.right.lessThanOrEqualTo(view.safeAreaLayoutGuide.snp.right).offset(-15)
        }

        self.view = view
    }

    func loadMarkers() {
        renderMarkers()
        self.checkClosestStation(latitude: self.currentLatitude, longitude: self.currentLongitude)
    }

    /// The markers on the map, one per station, kept between redraws.
    private var markers: [MarkerKey: StationMapMarker] = [:]

    /// Station ids are only unique within a country.
    struct MarkerKey: Hashable {
        let countryCode: String
        let stationId: Int
    }

    /// Brings every marker to the timeline's hour.
    ///
    /// Markers are kept and only those whose look changed are restyled, so
    /// stepping through the timeline (or a burst of history arriving) costs a
    /// handful of icon swaps rather than clearing the map and building every
    /// marker again (FOX-69).
    func renderMarkers() {
        var wanted: [MarkerKey: (pollutant: Pollutant, appearance: MarkerAppearance, isInteractive: Bool)] = [:]
        for (countryCode, pollutants) in self.countryPollutants {
            let isInteractive = countryCode == self.supportedCountryCode
            // Worked out once per country rather than per station.
            let hour = timelineHour(anchor: Self.anchor(of: pollutants))
            for livePollutant in pollutants {
                let (pollutant, hasData) = displayedPollutant(livePollutant, hour: hour)
                let appearance = MarkerAppearance(
                    pollutant: pollutant,
                    airIndexType: self.airIndexTypeSelected,
                    isWindMode: self.isWindMode,
                    isInteractive: isInteractive,
                    hasData: hasData
                )
                let key = MarkerKey(countryCode: countryCode, stationId: livePollutant.stationId)
                wanted[key] = (pollutant, appearance, isInteractive)
            }
        }

        let plan = MarkerUpdatePlan(current: Set(markers.keys), wanted: Set(wanted.keys))

        for key in plan.remove {
            markers[key]?.map = nil
            markers[key] = nil
        }
        for (key, station) in wanted {
            if plan.add.contains(key) {
                let marker = StationMapMarker(
                    pollutant: station.pollutant,
                    appearance: station.appearance,
                    isInteractive: station.isInteractive
                )
                marker.map = self.mapView
                markers[key] = marker
            } else {
                // Unchanged looks return early; the reading and whether it
                // opens are still swapped so a tap does the right thing.
                markers[key]?.update(
                    pollutant: station.pollutant,
                    appearance: station.appearance,
                    isInteractive: station.isInteractive
                )
            }
        }
        refreshHeatmap()
    }

    /// The publish hour the timeline is on for a country with this anchor, or
    /// `nil` at "now" (or before the country's readings are in).
    private func timelineHour(anchor: String?) -> String? {
        guard timelineHoursAgo > 0, let anchor else { return nil }
        return MapTimeline.publishTime(anchor, hoursAgo: timelineHoursAgo)
    }

    /// The latest publish hour among a country's stations — "now" on the
    /// timeline. Per country, since each publishes in its own wall-clock time.
    private static func anchor(of pollutants: Pollutants) -> String? {
        pollutants.lazy.map(\.publishTime).max()
    }

    private func anchor(forStation stationId: Int) -> String? {
        countryPollutants.values
            .first { $0.contains { $0.stationId == stationId } }
            .flatMap(Self.anchor(of:))
    }

    /// What a station shows at the timeline's hour, and whether there is a
    /// reading behind it. Live at "now"; that hour's history otherwise.
    private func displayedPollutant(_ live: Pollutant) -> (pollutant: Pollutant, hasData: Bool) {
        displayedPollutant(live, hour: timelineHour(anchor: anchor(forStation: live.stationId)))
    }

    /// As above, for an hour already worked out (`nil` is live).
    private func displayedPollutant(_ live: Pollutant, hour: String?) -> (pollutant: Pollutant, hasData: Bool) {
        guard let hour else { return (live, true) }
        let reading = historyStore.reading(stationId: live.stationId, hour: hour)
        return (Pollutant(live, reading: reading, publishTime: hour), reading != nil)
    }

    /// The timeline is labelled in the supported country's clock (Taiwan).
    private func updateTimelineAnchor() {
        let pollutants = supportedCountryCode.flatMap { countryPollutants[$0] }
            ?? countryPollutants.values.first
        timelineView?.anchor = pollutants.flatMap(Self.anchor(of:))
    }

    /// Queues history for the stations in view, nearest the centre first.
    /// Stations off screen wait until the map is panned to them.
    private func requestVisibleHistory() {
        let bounds = GMSCoordinateBounds(region: mapView.projection.visibleRegion())
        let center = mapView.camera.target

        var wanted: [(stationId: Int, anchor: String, distance: Double)] = []
        for pollutants in countryPollutants.values {
            guard let anchor = Self.anchor(of: pollutants) else { continue }
            for pollutant in pollutants {
                let coordinate = CLLocationCoordinate2D(latitude: pollutant.lat, longitude: pollutant.lon)
                guard bounds.contains(coordinate) else { continue }
                let distance = pow(pollutant.lat - center.latitude, 2) + pow(pollutant.lon - center.longitude, 2)
                wanted.append((pollutant.stationId, anchor, distance))
            }
        }

        historyStore.request(wanted.sorted { $0.distance < $1.distance }.map { ($0.stationId, $0.anchor) })
    }

    /// History arrived for some stations. Coalesced, so a burst of responses
    /// is one redraw rather than one per station.
    private var historyRedrawScheduled = false

    private func historyDidChange() {
        let progress = historyStore.progress
        timelineView.progress = historyStore.isLoading ? progress : nil

        guard timelineHoursAgo > 0, !historyRedrawScheduled else { return }
        historyRedrawScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.historyRedrawScheduled = false
            self.renderMarkers()
            self.loadClosestStationView()
        }
    }

    /// Steps forward an hour at a time to "now". From "now", starts 24 hours back.
    private func togglePlay() {
        if playTimer != nil {
            stopPlaying()
            return
        }

        requestVisibleHistory()
        if timelineHoursAgo == 0 {
            timelineHoursAgo = MapHistoryStore.hours
        }
        timelineView.isPlaying = true
        TrackingManager.logEvent(.mapTimelinePlay)

        playTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Holds while the hour on screen is still filling in, so playback
            // doesn't race ahead of a cold cache.
            if self.historyStore.isLoading, self.historyStore.progress.done == 0 { return }
            self.timelineHoursAgo = max(self.timelineHoursAgo - 1, 0)
            if self.timelineHoursAgo == 0 {
                self.stopPlaying()
            }
        }
    }

    private func stopPlaying() {
        playTimer?.invalidate()
        playTimer = nil
        timelineView.isPlaying = false
    }

    func checkClosestStation(latitude: Double, longitude: Double) {
        var distance: Double = .greatestFiniteMagnitude

        var tempClosestPollutant = self.closestPollutant
        for (_, pollutants) in self.countryPollutants {
            pollutants.forEach { pollutant in
                let tempDistance = pow(pollutant.lat - latitude, 2) + pow(pollutant.lon - longitude, 2)
                if tempDistance < distance {
                    tempClosestPollutant = pollutant
                    distance = tempDistance
                }
            }
        }

        if let closestPollutant = tempClosestPollutant {
            self.closestPollutant = closestPollutant
            // Last good readings stay on the map; the widgets keep whatever
            // they last had, which may be newer.
            if !isLastGood(stationId: closestPollutant.stationId) {
                WidgetBridge.publish(
                    pollutants: self.liveCountryPollutants,
                    closest: closestPollutant
                )
            }
        }
    }

    private var closestStationHeight: Constraint?
    private var weatherWorkItem: DispatchWorkItem?

    /// `mapView(_:idleAt:)` fires repeatedly while the camera settles, so the
    /// weather for the centre is looked up once it has been still for a moment.
    func scheduleCenterWeather() {
        weatherWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.updateCenterWeather() }
        weatherWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    /// Weather is the current reading, so it is hidden while the timeline is
    /// scrubbed back. `StationWeatherStore` answers from its saved file when
    /// the request fails, and with nil (row hidden) when there is none: the
    /// card is never blocked on it.
    private func updateCenterWeather() {
        guard timelineHoursAgo == 0 else {
            showCenterWeather(nil, hint: nil)
            return
        }
        StationWeatherStore.shared.weather { [weak self] file in
            guard let self = self else { return }
            guard self.timelineHoursAgo == 0 else { return }
            let weather = file.flatMap {
                MapCenterWeather.make(lat: self.currentLatitude, lon: self.currentLongitude, in: $0)
            }
            self.showCenterWeather(weather, hint: file.flatMap { self.windHint(in: $0) })
        }
    }

    /// "Air is coming from…" for the card: only with the wind layer on, and
    /// when `WindLayer.hint` finds the wind and the stations upwind clear.
    private func windHint(in file: WeatherFile) -> String? {
        guard windLayerOn, let closest = closestPollutant else { return nil }
        let stations = countryPollutants.values.flatMap { $0 }
            .map { (lat: $0.lat, lon: $0.lon, pm25: $0.pm25) }
        return WindLayer.hint(
            lat: currentLatitude, lon: currentLongitude,
            localPm25: closest.pm25, stations: stations, in: file
        ).map { WindLayer.hintText($0) }
    }

    private func showCenterWeather(_ weather: MapCenterWeather?, hint: String?) {
        // The hint sits under the weather row, so it needs the row.
        let hint = weather == nil ? nil : hint
        guard weather != closestStationView.weather || hint != closestStationView.windHint else { return }
        closestStationView.weather = weather
        closestStationView.windHint = hint
        updateClosestStationHeight()
    }

    private func updateClosestStationHeight() {
        closestStationHeight?.update(offset: ClosestStationView.height(
            weather: closestStationView.weather,
            hasHint: closestStationView.windHint != nil,
            hasAdvice: closestStationView.advice != nil
        ))
        view.layoutIfNeeded()
    }

    /// The station the top-left card opens, nil when there is nothing to open.
    private var closestCardStationId: Int? {
        guard let live = closestPollutant else { return nil }
        return MapCardTarget.stationId(
            closest: live,
            supportedCountryCode: supportedCountryCode,
            countryPollutants: countryPollutants,
            hasReading: displayedPollutant(live).hasData
                && displayedPollutant(live).pollutant.getValue(airIndexType: airIndexTypeSelected) != 0
        )
    }

    @objc private func closestStationTapped() {
        guard let stationId = closestCardStationId else { return }
        TrackingManager.logEvent(.checkMainDetails, parameters: [
            "name": closestPollutant.name,
            "nameLocal": closestPollutant.nameLocal,
            "stationId": stationId,
            "label": "card",
        ])
        onStationSelected?(stationId)
    }

    /// The card's one line of advice (TWAQ-13), nil when switched off in Help or there is no reading.
    private func adviceText(for status: AirStatuses, hasReading: Bool) -> String? {
        guard hasReading, defaults.object(forKey: SettingsStore.showsAdviceKey) as? Bool ?? true else { return nil }
        return status.adviceKey?.localized
    }

    func loadClosestStationView() {
        defer { closestStationView.isEnabled = closestCardStationId != nil }
        if let livePollutant = self.closestPollutant {
            let closestPollutant = displayedPollutant(livePollutant).pollutant
            let value = closestPollutant.getValue(airIndexType: self.airIndexTypeSelected)
            let text = value != 0 ? value.format(f: self.airIndexTypeSelected.getFormat()) : "-" 
            let airStatus = AirStatuses.checkAirStatus(
                airIndexType: self.airIndexTypeSelected,
                value: value
            )

            closestStationView.stationName = closestPollutant.displayName
            closestStationView.locality = closestPollutant.displayLocality
            closestStationView.publishTime = closestPollutant.publishTime
            closestStationView.isLastGood = isLastGood(stationId: livePollutant.stationId)
            closestStationView.timelineContext = timelineHoursAgo > 0
                ? anchor(forStation: livePollutant.stationId)
                    .flatMap { MapTimeline.describe(anchor: $0, hoursAgo: timelineHoursAgo) }
                    .map { "\($0.clock)・\($0.relative)" }
                : nil
            closestStationView.status = "AirStatus.\(airStatus.rawValue)".localized
            // Only for the AQI, whose levels the guidance is written for (the header uses it too),
            // and not while the timeline shows a past hour: the sentence is present tense.
            closestStationView.advice = adviceText(
                for: airStatus,
                hasReading: value != 0 && airIndexTypeSelected == .aqi && timelineHoursAgo == 0
            )
            closestStationView.aqi = "\(self.airIndexTypeSelected.toString()) \(text)"

            closestStationView.aqiColor = UIColor(rgb: Int(airStatus.getColor()))
            closestStationView.aqiForegroundColor = UIColor(rgb: Int(airStatus.getForegroundColor()))
            closestStationView.image = airStatus.hasFaceImage ? UIImage(named: airStatus.getImage()) : nil
        }
    }

    override func loadView() {
        // Prepare a map. The position marker is drawn by the app and its
        // updates start only once permission is given; the prompt itself comes
        // from the welcome flow's step or the locate-me button, never from here.
        locationTracker.onLocation = { [weak self] in self?.handleLocation($0) }
        locationTracker.onHeading = { [weak self] in self?.handleHeading($0) }
        locationTracker.onAccessChange = { [weak self] in self?.handleAccessChange($0) }
        mapView.settings.compassButton = true
        // Exposes the markers, by their titles, to VoiceOver.
        mapView.accessibilityElementsHidden = false

        applyMapStyle()

        self.callGetCountriesApi()

        mapView.delegate = self

        // Pro is re-checked with StoreKit after launch and can change at any
        // time (a purchase, a lapsed subscription, the developer override).
        // Reading it once here left a banner-sized gap once the ads went away.
        proObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateBannerClearance()
        }

        // Declining consent removes the banner too, and UMP answers after launch.
        // `$canRequestAds` publishes before the value is set, so re-read next turn.
        consentObserver = ConsentManager.shared.$canRequestAds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateBannerClearance() }

        startRefreshTimer()

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.locationTracker.setAppActive(true)
            self?.startRefreshTimer()
            self?.refreshAfterForeground()
        }

        // No polling while the app is in the background.
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.stopRefreshTimer()
            self?.locationTracker.setAppActive(false)
        }

        loadContent()
    }

    static let refreshInterval: TimeInterval = 60 * 15

    /// Arms the refresh timer. A timer paused by `stopRefreshTimer()` resumes
    /// on its saved fire date, so short background trips don't push the
    /// refresh back a full interval. An armed timer is left alone.
    func startRefreshTimer() {
        if let timer = refreshTimer, timer.isValid { return }
        let fireDate = pausedFireDate ?? Date().addingTimeInterval(Self.refreshInterval)
        pausedFireDate = nil
        let timer = Timer(fire: fireDate, interval: Self.refreshInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.countries.isEmpty {
                self.callGetCountriesApi()
            }
            for (countryCode, _) in self.countryPollutants {
                self.callGetCurrentPollutantsApi(countryCode: countryCode)
            }
        }
        RunLoop.main.add(timer, forMode: .default)
        refreshTimer = timer
    }

    func stopRefreshTimer() {
        if let timer = refreshTimer, timer.isValid {
            pausedFireDate = timer.fireDate
        }
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func updateBannerClearance() {
        let hasBanner = self.hasBanner
        guard hasBanner != hasBannerLayout else { return }
        hasBannerLayout = hasBanner
        bottomBarBottom?.update(offset: Self.bannerClearance(hasBanner: hasBanner))
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    /// Dark map in dark mode, Google's default otherwise.
    private func applyMapStyle() {
        guard traitCollection.userInterfaceStyle == .dark else {
            mapView.mapStyle = nil
            return
        }
        do {
            // Set the map style by passing a valid JSON string.
            mapView.mapStyle = try GMSMapStyle(jsonString: GoogleMapStyles.dark.rawValue)
        } catch {
            NSLog("One or more of the map styles failed to load. \(error)")
        }
    }

    /// The look can change while the map is open: Help's appearance picker
    /// (FOX-43), or the system switching between light and dark.
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyMapStyle()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.syncHeadingOrientation() }
        self.checkClosestStation(latitude: self.currentLatitude, longitude: self.currentLongitude)

        // From the sizes rather than `UIDevice.orientation`, which is still
        // the old one here (or face up), and only when the shape flips: a
        // window resized on iPad isn't a rotation.
        let isLandscape = size.width > size.height
        if isLandscape != (view.bounds.width > view.bounds.height) {
            TrackingManager.logEvent(.changeDeviceOrientation, parameters: [
                "label": isLandscape ? "landscape" : "portrait",
            ])
        }
    }

    // MARK: GMSMapViewDelegate
    func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
        guard let stationMarker = marker as? StationMarker else { return true }

        // Markers outside the supported country are context only.
        guard stationMarker.isInteractive else {
            return true
        }

        let pollutant = stationMarker.pollutant
        TrackingManager.logEvent(.checkMainDetails, parameters: [
            "name": pollutant.name,
            "nameLocal": pollutant.nameLocal,
            "stationId": pollutant.stationId,
        ])

        onStationSelected?(pollutant.stationId)
        return true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.width != lastLayoutWidth else { return }
        lastLayoutWidth = view.bounds.width
        // After the map has taken its new size, so the projection matches.
        DispatchQueue.main.async { [weak self] in
            self?.revealPanelStation()
        }
    }

    /// The map keeps its centre as the panel takes its width, so a station
    /// tapped near the panel's side can end up behind it. Pans to it then.
    private func revealPanelStation() {
        // Only the supported country's stations open, and ids are only
        // unique within a country.
        guard let stationId = panelStationId,
              let pollutant = supportedCountryCode
                .flatMap({ countryPollutants[$0] })?
                .first(where: { $0.stationId == stationId }) else { return }

        let coordinate = CLLocationCoordinate2D(latitude: pollutant.lat, longitude: pollutant.lon)
        // Clear of the edges, where the buttons and bars sit over the map.
        let clear = mapView.bounds.insetBy(dx: 80, dy: 80)
        guard !clear.contains(mapView.projection.point(for: coordinate)) else { return }
        mapView.animate(toLocation: coordinate)
    }

    /// Fades the heatmap with the zoom while pinching; one opacity write.
    func mapView(_ mapView: GMSMapView, didChange position: GMSCameraPosition) {
        heatmapOverlay.zoomChanged(position.zoom)
    }

    func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
        let latitude = position.target.latitude as Double
        let longitude = position.target.longitude as Double
        let zoom = position.zoom
        defaults.set(latitude, forKey: "lastestMapLat")
        defaults.set(longitude, forKey: "lastestMapLon")
        defaults.set(zoom, forKey: "lastestMapZoom")

        self.currentLatitude = latitude
        self.currentLongitude = longitude
        checkClosestCountry(latitude: latitude, longitude: longitude)
        checkClosestStation(latitude: latitude, longitude: longitude)
        scheduleCenterWeather()
        refreshWindLayer()
        heatmapOverlay.zoomChanged(position.zoom)

        // Panned back in time and on to new stations: fetch theirs too.
        if timelineHoursAgo > 0 {
            requestVisibleHistory()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(true)
        syncHeadingOrientation()
        // The advice switch lives in Help: pick up a change on coming back.
        if closestStationView != nil { loadClosestStationView() }
        self.navigationController?.setNavigationBarHidden(true, animated: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Position and compass run only while the map is showing.
        locationTracker.setVisible(true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPlaying()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        locationTracker.setVisible(false)
    }
}

struct GoogleMapController: UIViewControllerRepresentable {

    typealias UIViewControllerType = GoogleMapViewController

    var onStationSelected: ((Int) -> Void)?
    var panelStationId: Int?

    func makeUIViewController(context: UIViewControllerRepresentableContext<GoogleMapController>) -> GoogleMapViewController {
        GoogleMapViewController()
    }

    func updateUIViewController(_ uiViewController: GoogleMapViewController, context: UIViewControllerRepresentableContext<GoogleMapController>) {
        uiViewController.onStationSelected = onStationSelected
        uiViewController.panelStationId = panelStationId
    }
}
