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

let screenSize: CGRect = UIScreen.main.bounds
let isLandscape = UIDevice.current.orientation.isLandscape

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
    var windModeButton: WindModeButton!

    var currentLatitude: Double = GoogleMapViewController.initialCamera.target.latitude
    var currentLongitude: Double = GoogleMapViewController.initialCamera.target.longitude

    var countries: Countries = []
    var closestCountry: Country!

    /// Code of the country whose markers are openable. Resolved from the
    /// countries endpoint so the id -> code mapping stays server-driven.
    var supportedCountryCode: String?

    var pollutants: Pollutants = []

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
        }
    }

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
                print("Total Countries: \(result.count), first item \(result[0])")
            case .failure(let error):
                print(error.localizedDescription)
            }
        }
    }

    func callGetCurrentPollutantsApi(countryCode: String) {
        APIManager.getCurrentPollutants(countryCode: countryCode) { result in
            switch result {
            case .success(let result):
                print("callGetCurrentPollutantsApi Total: \(result.count)")
                self.countryPollutants[countryCode] = result
            case .failure(let error):
                print(error.localizedDescription)
            }
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

    func loadContent(
        width: CGFloat = UIScreen.main.bounds.width,
        height: CGFloat = UIScreen.main.bounds.height,
        isLandscape: Bool = UIDevice.current.orientation.isLandscape
    ) {
        mapView.frame = CGRect(x: 0, y: 0, width: width, height: height)

        let view = UIView()
        view.backgroundColor = .white
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
        let airIndexTypeSelected = defaults.string(forKey: "airIndexTypeSelected")
            .flatMap { AirIndexTypes(rawValue: $0) } ?? .aqi

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
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).offset(isPro ? -10 : -60)
            make.width.equalTo(view.safeAreaLayoutGuide.snp.width)
            make.height.equalTo(IndexSelectorView.preferredHeight)
            if width > 610 {
                make.left.equalTo(view.snp.left).offset(width/2 - 305)
            } else {
                make.left.equalTo(view.safeAreaLayoutGuide.snp.left)
            }
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
        print("loadMarkers")
        self.mapView.clear()
        for (countryCode, pollutants) in self.countryPollutants {
            let isInteractive = countryCode == self.supportedCountryCode
            pollutants.forEach { pollutant in
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
                pollutantMarker.tracksViewChanges = false
                pollutantMarker.map = self.mapView
            }
        }

        self.checkClosestStation(latitude: self.currentLatitude, longitude: self.currentLongitude)
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
        }
    }

    func loadClosestStationView() {
        if let closestPollutant = self.closestPollutant {
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
        // mapView.settings.myLocationButton = true

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

        Timer.scheduledTimer(withTimeInterval: 60 * 15, repeats: true) { (_) in
            // Schedule in seconds
            for (countryCode, _) in self.countryPollutants {
                self.callGetCurrentPollutantsApi(countryCode: countryCode)
            }
        }

        loadContent()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        if UIDevice.current.orientation.isLandscape {
            print("Landscape", size.width, UIDevice.current.orientation, screenSize)
            loadContent(width: size.width, height: size.height, isLandscape: true)
        } else {
            print("Portrait", size, UIDevice.current.orientation, screenSize)
            loadContent(width: size.width, height: size.height, isLandscape: false)
        }

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

        let detailsView = DetailsView(stationId: pollutant.stationId)
        let detailsViewController = UIHostingController(rootView: detailsView.environmentObject(SettingsStore()))
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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(true)
        self.navigationController?.setNavigationBarHidden(true, animated: true)
    }
}

struct GoogleMapController: UIViewControllerRepresentable {

    typealias UIViewControllerType = GoogleMapViewController

    func makeUIViewController(context: UIViewControllerRepresentableContext<GoogleMapController>) -> GoogleMapViewController {
        // Create the `GoogleMapViewController`.
        return GoogleMapViewController()
    }

    func updateUIViewController(_ uiViewController: GoogleMapViewController, context: UIViewControllerRepresentableContext<GoogleMapController>) {
        // Update the view controller.
    }
}
