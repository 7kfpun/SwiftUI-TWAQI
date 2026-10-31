//
//  GoogleMapController.swift
//  TWAQI
//
//  Created by kf on 2/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

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

    let mapView = GMSMapView.map(withFrame: .zero, camera: GoogleMapViewController.initialCamera)

    var closestStationView: ClosestStationView!
    var defaultLocationButton: DefaultLocationButton!
    var indexSelectorView: IndexSelectorView!
    var myLocationButton: MyLocationButton!
    var timelineView: MapTimelineView!
    var windModeButton: WindModeButton!

    /// The timeline bar sits above the ad banner, which SwiftUI lays out
    /// outside this map, with the index bar on top of it. Kept so both can drop
    /// down when the banner goes away.
    private var bottomBarBottom: Constraint?
    private var proObserver: NSObjectProtocol?
    private var isProLayout = false

    /// Gap between the index bar and the tab bar, plus the banner when shown.
    private static func bannerClearance(isPro: Bool) -> CGFloat {
        isPro ? -10 : -(AdBannerView.height + 10)
    }

    var currentLatitude: Double = GoogleMapViewController.initialCamera.target.latitude
    var currentLongitude: Double = GoogleMapViewController.initialCamera.target.longitude

    var countries: Countries = []
    var closestCountry: Country!

    /// Code of the country whose markers are openable. Resolved from the
    /// countries endpoint so the id -> code mapping stays server-driven.
    var supportedCountryCode: String?

    var pollutants: Pollutants = []

    /// Set while the map shares a wide window with a station panel. A tapped
    /// station goes to the panel instead of a sheet over the map.
    var onStationSelected: ((Int) -> Void)?

    /// The app's shared store, handed down from SwiftUI, for the station sheet.
    /// A fresh `SettingsStore()` there was a second instance outside the app's
    /// environment. Always set by `GoogleMapController`.
    var settings: SettingsStore?

    @objc func toggleIsWindMode() {
        self.isWindMode = !self.isWindMode
        TrackingManager.logEvent(eventName: "set_wind_mode", parameters: ["label": self.isWindMode ? "on" : "off"])
    }

    @objc func goToMyLocation(isSkipLog: Bool = false) {
        if let mylocation = self.mapView.myLocation {
            print("User's location: \(mylocation)")
            let mylocationCamera = GMSCameraPosition.camera(
                withLatitude: mylocation.coordinate.latitude,
                longitude: mylocation.coordinate.longitude,
                zoom: 13
            )
            self.currentLatitude = mylocation.coordinate.latitude
            self.currentLongitude = mylocation.coordinate.longitude
            self.mapView.animate(to: mylocationCamera)

            if !isSkipLog {
                TrackingManager.logEvent(eventName: "move_to_current_location")
            }
        } else {
            print("User's location is unknown")
        }
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
        TrackingManager.logEvent(eventName: "move_to_default_location")
    }

    @objc func changeIndex(sender: UIButton?) {
        if let tag = sender?.tag {
            let airIndexTypes = AirIndexTypes.allCases[tag]
            print(tag, airIndexTypes)
            self.airIndexTypeSelected = airIndexTypes

            indexSelectorView.setSelected(tag: tag)

            TrackingManager.logEvent(eventName: "select_index", parameters: ["label": airIndexTypes.rawValue])
        }
    }

    @objc func dismissModal() {
        self.dismiss(animated: true, completion: nil)
    }

    var isWindMode = false {
        didSet {
            windModeButton.isWindMode = isWindMode
            loadMarkers()
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
            loadMarkers()
            updateTimelineAnchor()
            // A new publish hour moves the window; top up what's in view.
            if timelineHoursAgo > 0 {
                requestVisibleHistory()
            }
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
        }
    }

    private var playTimer: Timer?

    var closestPollutant: Pollutant! {
        didSet {
            loadClosestStationView()
        }
    }

    func callGetCountriesApi() {
        APIManager.getCountries { result in
            switch result {
            case .success(let result):
                self.countries = result

                if let supported = result.first(where: { $0.isSupported }) {
                    self.supportedCountryCode = supported.code
                    // The search tab lists stations for this country rather than
                    // whichever country the map happens to be panned over.
                    defaults.set(supported.code, forKey: "supportedCountryCode")
                    self.callGetCurrentPollutantsApi(countryCode: supported.code)
                }

                self.checkClosestCountry(latitude: self.currentLatitude, longitude: self.currentLongitude)
                self.loadMarkers()
                print("Total Countries: \(result.count)")
            case .failure(let error):
                print(error.localizedDescription)
                // Offline launch: the country list is only needed to know
                // which country to load, and the last answer is saved. Its
                // pollutants request falls back to the last good readings.
                // The list itself is asked for again on the next foreground.
                if self.supportedCountryCode == nil,
                   let code = defaults.string(forKey: "supportedCountryCode"), !code.isEmpty {
                    self.supportedCountryCode = code
                    self.callGetCurrentPollutantsApi(countryCode: code)
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

    func callGetCurrentPollutantsApi(countryCode: String) {
        guard !pollutantRequestsInFlight.contains(countryCode) else { return }
        pollutantRequestsInFlight.insert(countryCode)

        APIManager.getCurrentPollutants(countryCode: countryCode) { result in
            self.pollutantRequestsInFlight.remove(countryCode)

            switch result {
            case .success(let result):
                print("callGetCurrentPollutantsApi Total: \(result.count)")
                self.lastGoodCountryCodes.remove(countryCode)
                self.countryPollutants[countryCode] = result
                WidgetBridge.publish(
                    pollutants: self.liveCountryPollutants,
                    closest: self.liveClosestPollutant
                )
            case .failure(let error):
                print(error.localizedDescription)
                // Keep what is on screen; with nothing on screen yet, show the
                // last good readings rather than an empty map.
                if self.countryPollutants[countryCode] == nil {
                    guard let cached = PollutantCache.shared.pollutants(countryCode: countryCode) else { return }
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
        view.addSubview(closestStationView)
        closestStationView.snp.makeConstraints { (make) -> Void in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(8)
            make.left.equalTo(view.safeAreaLayoutGuide.snp.left).offset(15)
            make.width.equalTo(ClosestStationView.preferredSize.width)
            make.height.equalTo(ClosestStationView.preferredSize.height)
        }

        // MARK: airStatusesView
        let airStatusesView = AirStatusBarView()
        view.addSubview(airStatusesView)
        airStatusesView.snp.makeConstraints { (make) -> Void in
            make.top.equalTo(closestStationView.snp.bottom).offset(8)
            make.left.equalTo(view.safeAreaLayoutGuide.snp.left).offset(15)
            make.width.equalTo(ClosestStationView.preferredSize.width)
            make.height.equalTo(32)
        }

        let isPro = defaults.bool(forKey: "pro")
        isProLayout = isPro
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
                .offset(Self.bannerClearance(isPro: isPro)).constraint
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
        myLocationButton.button.addTarget(self, action: #selector(goToMyLocation), for: .touchUpInside)

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

        self.view = view
    }

    func loadMarkers() {
        renderMarkers()
        self.checkClosestStation(latitude: self.currentLatitude, longitude: self.currentLongitude)
    }

    /// Redraws every marker at the timeline's hour.
    func renderMarkers() {
        print("renderMarkers", timelineHoursAgo)
        self.mapView.clear()
        for (countryCode, pollutants) in self.countryPollutants {
            let isInteractive = countryCode == self.supportedCountryCode
            let anchor = Self.anchor(of: pollutants)
            pollutants.forEach { livePollutant in
                let (pollutant, hasData) = displayedPollutant(livePollutant, anchor: anchor)
                var pollutantMarker: GMSMarker
                if self.isWindMode {
                    pollutantMarker = WindDirectionMarker(
                        pollutant: pollutant,
                        airIndexTypeSelected: self.airIndexTypeSelected,
                        isInteractive: isInteractive
                    )
                } else {
                    pollutantMarker = PollutantMarker(
                        pollutant: pollutant,
                        airIndexTypeSelected: self.airIndexTypeSelected,
                        isInteractive: isInteractive
                    )
                }
                if !hasData {
                    // Not loaded yet, or no reading that hour: grey "-", faded
                    // so it reads as missing rather than as a reading.
                    pollutantMarker.opacity = min(pollutantMarker.opacity, 0.55)
                }
                pollutantMarker.tracksViewChanges = false
                pollutantMarker.map = self.mapView
            }
        }
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
    private func displayedPollutant(_ live: Pollutant, anchor: String? = nil) -> (pollutant: Pollutant, hasData: Bool) {
        guard timelineHoursAgo > 0,
              let anchor = anchor ?? self.anchor(forStation: live.stationId),
              let target = MapTimeline.publishTime(anchor, hoursAgo: timelineHoursAgo) else {
            return (live, true)
        }

        let reading = historyStore.reading(stationId: live.stationId, publishTime: target)
        return (Pollutant(live, reading: reading, publishTime: target), reading != nil)
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
        TrackingManager.logEvent(eventName: "map_timeline_play")

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
        print("checkClosestStation")
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
            print("checkClosestStation", closestPollutant)
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

    func loadClosestStationView() {
        if let livePollutant = self.closestPollutant {
            let closestPollutant = displayedPollutant(livePollutant).pollutant
            print("loadClosestStationView", closestPollutant)
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
            closestStationView.aqi = "\(self.airIndexTypeSelected.toString()) \(text)"

            closestStationView.aqiColor = UIColor(rgb: Int(airStatus.getColor()))
            closestStationView.aqiForegroundColor = UIColor(rgb: Int(airStatus.getForegroundColor()))
            closestStationView.image = airStatus.hasFaceImage ? UIImage(named: airStatus.getImage()) : nil
        }
    }

    override func loadView() {
        // Prepare a map
        mapView.isMyLocationEnabled = true
        mapView.settings.compassButton = true
        // Exposes the markers, by their titles, to VoiceOver.
        mapView.accessibilityElementsHidden = false

        if self.traitCollection.userInterfaceStyle == .dark {
            // User Interface is Dark
            do {
                // Set the map style by passing a valid JSON string.
                mapView.mapStyle = try GMSMapStyle(jsonString: GoogleMapStyles.dark.rawValue)
            } catch {
                NSLog("One or more of the map styles failed to load. \(error)")
            }
        }

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

        Timer.scheduledTimer(withTimeInterval: 60 * 15, repeats: true) { (_) in
            // Schedule in seconds
            if self.countries.isEmpty {
                self.callGetCountriesApi()
            }
            for (countryCode, _) in self.countryPollutants {
                self.callGetCurrentPollutantsApi(countryCode: countryCode)
            }
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshAfterForeground()
        }

        loadContent()
    }

    private func updateBannerClearance() {
        let isPro = defaults.bool(forKey: "pro")
        guard isPro != isProLayout else { return }
        isProLayout = isPro
        bottomBarBottom?.update(offset: Self.bannerClearance(isPro: isPro))
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        self.checkClosestStation(latitude: self.currentLatitude, longitude: self.currentLongitude)

        TrackingManager.logEvent(eventName: "change_device_orientation", parameters: [
            "label": UIDevice.current.orientation.isLandscape ? "landscape" : "portrait",
        ])
    }

    // MARK: GMSMapViewDelegate
    func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
        print("You tapped at \(coordinate.latitude), \(coordinate.longitude)")
    }

    func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
        guard let stationMarker = marker as? StationMarker else { return true }

        // Markers outside the supported country are context only.
        guard stationMarker.isInteractive else {
            print("Marker tapped but not openable (outside supported country)", stationMarker.pollutant.stationId)
            return true
        }

        let pollutant = stationMarker.pollutant
        print("Marker tapped", pollutant.stationId)

        TrackingManager.logEvent(eventName: "check_main_details", parameters: [
            "name": pollutant.name,
            "nameLocal": pollutant.nameLocal,
            "stationId": pollutant.stationId,
        ])

        if let onStationSelected = onStationSelected {
            onStationSelected(pollutant.stationId)
            return true
        }

        let detailsView = DetailsView(stationId: pollutant.stationId)
        // Outside the SwiftUI tree, so the Help language has to be passed in.
        let detailsViewController = UIHostingController(
            // The fallback only for a controller built outside SwiftUI; every
            // store reads the same defaults, so it behaves the same.
            rootView: detailsView
                .environmentObject(settings ?? SettingsStore())
                .environment(\.locale, .app)
        )
        detailsViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissModal)
        )
        let detailsViewNavigationController = UINavigationController(rootViewController: detailsViewController)
        self.present(detailsViewNavigationController, animated: true, completion: nil)

        return true
    }

    func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
        print("Camera position", position)
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

        // Panned back in time and on to new stations: fetch theirs too.
        if timelineHoursAgo > 0 {
            requestVisibleHistory()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(true)
        self.navigationController?.setNavigationBarHidden(true, animated: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPlaying()
    }
}

struct GoogleMapController: UIViewControllerRepresentable {

    typealias UIViewControllerType = GoogleMapViewController

    var onStationSelected: ((Int) -> Void)?

    /// The app's shared store, passed through to the station sheet.
    @EnvironmentObject var settings: SettingsStore

    func makeUIViewController(context: UIViewControllerRepresentableContext<GoogleMapController>) -> GoogleMapViewController {
        let controller = GoogleMapViewController()
        controller.settings = settings
        return controller
    }

    func updateUIViewController(_ uiViewController: GoogleMapViewController, context: UIViewControllerRepresentableContext<GoogleMapController>) {
        uiViewController.onStationSelected = onStationSelected
        uiViewController.settings = settings
    }
}
