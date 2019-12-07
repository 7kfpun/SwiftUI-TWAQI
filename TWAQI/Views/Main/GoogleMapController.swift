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
let defaultLatitude = defaults.double(forKey: "lastestMapLat")
let defaultLongitude = defaults.double(forKey: "lastestMapLon")
let lastestMapZoom = defaults.float(forKey: "lastestMapZoom")
let camera = GMSCameraPosition.camera(withLatitude: defaultLatitude, longitude: defaultLongitude, zoom: lastestMapZoom)

let screenSize: CGRect = UIScreen.main.bounds
let isLandscape = UIDevice.current.orientation.isLandscape

class GoogleMapViewController: UIViewController, GMSMapViewDelegate {
    let mapView = GMSMapView.map(withFrame: .zero, camera: camera)

    var closestStationView: ClosestStationView!
    var defaultLocationButton: DefaultLocationButton!
    var indexSelectorView: IndexSelectorView!
    var myLocationButton: MyLocationButton!
    var windModeButton: WindModeButton!

    var currentLatitude: Double = defaultLatitude
    var currentLongitude: Double = defaultLongitude

    var countries: Countries = []
    var closestCountry: Country!

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
        if let closestCountry = closestCountry {
            let defaultCamera = GMSCameraPosition.camera(
                withLatitude: closestCountry.lat,
                longitude: closestCountry.lon,
                zoom: closestCountry.zoom
            )
            self.mapView.animate(to: defaultCamera)
        } else {
            // Taiwan Location
            let defaultCamera = GMSCameraPosition.camera(withLatitude: 23.49, longitude: 120.96, zoom: 7.9)
            self.mapView.animate(to: defaultCamera)
        }
        TrackingManager.logEvent(eventName: "move_to_default_location")
    }

    @objc func changeIndex(sender: UIButton?) {
        if let tag = sender?.tag {
            let airIndexTypes = AirIndexTypes.allCases[tag]
            print(tag, airIndexTypes)
            self.airIndexTypeSelected = airIndexTypes

            for button in indexSelectorView.buttons {
                button.setTitleColor(button.tag == tag ? UIColor(rgb: 0x5AC8FA) : .label, for: .normal)
            }

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
                self.checkClosestCountry(latitude: defaultLatitude, longitude: defaultLongitude)
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
        if !self.countries.isEmpty {
            var closestCountry: Country = self.countries.first!
            var distance: Double = .greatestFiniteMagnitude
            self.countries.forEach { country in
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
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(5)
            make.left.equalTo(view.safeAreaLayoutGuide.snp.left).offset(15)
            make.width.equalTo(200)
            make.height.equalTo(75)
        }

        // MARK: airStatusesView
        let airStatusesView = AirStatusBarView()
        view.addSubview(airStatusesView)
        airStatusesView.snp.makeConstraints { (make) -> Void in
            make.top.equalTo(closestStationView.snp.bottom).offset(8)
            make.left.equalTo(view.safeAreaLayoutGuide.snp.left).offset(15)
            make.width.equalTo(200)
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
                indexSelectorView.buttons[i].setTitleColor(UIColor(rgb: 0x5AC8FA), for: .normal)
            }
        }
        view.addSubview(indexSelectorView)
        indexSelectorView.snp.makeConstraints { (make) -> Void in
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).offset(isPro ? -10 : -60)
            make.width.equalTo(view.safeAreaLayoutGuide.snp.width)
            make.height.equalTo(54)
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
        for (_, pollutants) in self.countryPollutants {
            pollutants.forEach { pollutant in
                var pollutantMarker: GMSMarker
                if self.isWindMode {
                    pollutantMarker = WindDirectionMarker(pollutant: pollutant, airIndexTypeSelected: self.airIndexTypeSelected)
                } else {
                    pollutantMarker = PollutantMarker(pollutant: pollutant, airIndexTypeSelected: self.airIndexTypeSelected)
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

            closestStationView.stationName = Locale.isChinese ? closestPollutant.nameLocal : closestPollutant.name
            closestStationView.status = "AirStatus.\(airStatus.rawValue)".localized
            closestStationView.aqi = "\(self.airIndexTypeSelected.toString()) \(text)"

            closestStationView.aqiColor = UIColor(rgb: Int(airStatus.getColor()))
            closestStationView.aqiForegroundColor = UIColor(rgb: Int(airStatus.getForegroundColor()))
            closestStationView.image = UIImage(named: airStatus.getImage())
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
        self.callGetCurrentPollutantsApi(countryCode: "twn")

        mapView.delegate = self

        Timer.scheduledTimer(withTimeInterval: 60 * 15, repeats: true) { (_) in
            // Schedule in seconds
            for (countryCode, _) in self.countryPollutants {
                self.callGetCurrentPollutantsApi(countryCode: countryCode)
            }
        }

        loadContent()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.goToMyLocation(isSkipLog: true)
        }
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
        var detailsView: DetailsView
        if isWindMode {
            let mmarker = marker as! WindDirectionMarker
            print("Marker tapped", marker, mmarker.pollutant.stationId)
            detailsView = DetailsView(stationId: mmarker.pollutant.stationId)
            TrackingManager.logEvent(eventName: "check_main_details", parameters: [
                "name": mmarker.pollutant.name,
                "nameLocal": mmarker.pollutant.nameLocal,
                "stationId": mmarker.pollutant.stationId,
            ])
        } else {
            let mmarker = marker as! PollutantMarker
            print("Marker tapped", marker, mmarker.pollutant.stationId)
            detailsView = DetailsView(stationId: mmarker.pollutant.stationId)
            TrackingManager.logEvent(eventName: "check_main_details", parameters: [
                "name": mmarker.pollutant.name,
                "nameLocal": mmarker.pollutant.nameLocal,
                "stationId": mmarker.pollutant.stationId,
            ])
        }

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
