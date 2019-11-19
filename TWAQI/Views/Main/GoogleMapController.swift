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

let defaultLatitude = 23.49
let defaultLongitude = 120.96
let camera = GMSCameraPosition.camera(withLatitude: defaultLatitude, longitude: defaultLongitude, zoom: 7.9)
let screenSize: CGRect = UIScreen.main.bounds
let isLandscape = UIDevice.current.orientation.isLandscape

class GoogleMapViewController: UIViewController, GMSMapViewDelegate {

    let mapView = GMSMapView.map(withFrame: .zero, camera: camera)
    let defaults = UserDefaults.standard

    var closestStationView: ClosestStationView!
    var defaultLocationButton: DefaultLocationButton!
    var indexSelectorView: IndexSelectorView!
    var myLocationButton: MyLocationButton!
    var windModeButton: WindModeButton!

    var currentLatitude: Double = defaultLatitude
    var currentLongitude: Double = defaultLongitude

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
        self.mapView.animate(to: camera)
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

            loadClosestStationView(latitude: self.currentLatitude, longitude: self.currentLongitude)

            TrackingManager.logEvent(eventName: "select_index", parameters: ["label": airIndexTypes.rawValue])
        }
    }

    @objc func dismissModal() {
        self.dismiss(animated: true, completion: nil)
    }

    var isWindMode = false {
        didSet {
            windModeButton.isWindMode = isWindMode
            update()
        }
    }

    var airIndexTypeSelected: AirIndexTypes {
        get {
            return defaults.string(forKey: "airIndexTypeSelected")
                .flatMap { AirIndexTypes(rawValue: $0) } ?? .aqi
        }

        set {
            defaults.set(newValue.rawValue, forKey: "airIndexTypeSelected")
            update()
        }
    }

    func update() {
        self.mapView.clear()
        self.pollutants.forEach { pollutant in
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

    func callApi() {
        APIManager.getAQI { result in
            switch result {
            case .success(let result):
                self.pollutants = result
                print("Total: \(result.count), first item \(result[0])")
                self.update()
                self.loadClosestStationView(latitude: defaultLatitude, longitude: defaultLongitude)
            case .failure(let error):
                print(error.localizedDescription)
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

    func loadClosestStationView(latitude: Double, longitude: Double) {
        if !self.pollutants.isEmpty {
            var closestPollutant: Pollutant = self.pollutants.first!
            var distance: Double = .greatestFiniteMagnitude
            self.pollutants.forEach { pollutant in
                print(pollutant.latitude, pollutant.longitude)
                let platitude = Double(pollutant.latitude) ?? 0
                let plongitude = Double(pollutant.longitude) ?? 0

                if pow(platitude - latitude, 2) + pow(plongitude - longitude, 2) < distance {
                    closestPollutant = pollutant
                    distance = pow(platitude - latitude, 2) + pow(plongitude - longitude, 2)
                }
            }

            print(closestPollutant)
            defaults.set(closestPollutant.siteName, forKey: "closestStationName")

            let value = closestPollutant.getValue(airIndexType: self.airIndexTypeSelected)
            let isInteger = floor(value) == value
            let text = value.format(f: isInteger ? ".0" : ".2")

            closestStationView.stationName = "\(closestPollutant.siteName), \(closestPollutant.county)"
            closestStationView.status = closestPollutant.status
            closestStationView.aqi = "\(self.airIndexTypeSelected.toString()) \(text)"
            let airStatus = AirStatuses.checkAirStatus(
                airIndexType: self.airIndexTypeSelected,
                value: value
            )
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

        mapView.delegate = self

        self.callApi()
        Timer.scheduledTimer(withTimeInterval: 60 * 5, repeats: true) { (_) in
            // Schedule in seconds
            self.callApi()
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
        callApi()
    }

    // MARK: GMSMapViewDelegate
    func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
        print("You tapped at \(coordinate.latitude), \(coordinate.longitude)")
    }

    func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
        var detailsView: DetailsView
        if isWindMode {
            let mmarker = marker as! WindDirectionMarker
            print("Marker tapped", marker, mmarker.pollutant.siteName)
            detailsView = DetailsView(station: mmarker.pollutant.getStation())
        } else {
            let mmarker = marker as! PollutantMarker
            print("Marker tapped", marker, mmarker.pollutant.siteName)
            detailsView = DetailsView(station: mmarker.pollutant.getStation())
            TrackingManager.logEvent(eventName: "check_main_details", parameters: [
                // "name": mmarker.pollutant.siteName,
                "nameLocal": mmarker.pollutant.siteName,
            ])
        }

        let detailsViewController = UIHostingController(rootView: detailsView.environmentObject(SettingsStore()))
        detailsViewController.navigationItem.rightBarButtonItem = UIBarButtonItem(
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
        self.currentLatitude = latitude
        self.currentLongitude = longitude
        loadClosestStationView(latitude: latitude, longitude: longitude)
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
