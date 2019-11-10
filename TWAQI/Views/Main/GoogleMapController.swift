//
//  GoogleMapController.swift
//  TWAQI
//
//  Created by kf on 2/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import GoogleMaps
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
    var functionalButtonsView: FunctionalButtonsView!
    var indexSelectorView: IndexSelectorView!

    var pollutants: Pollutants = []

    @objc func toggleIsWindMode() {
        self.isWindMode = !self.isWindMode
    }

    @objc func goToMyLocation() {
        if let mylocation = self.mapView.myLocation {
            print("User's location: \(mylocation)")
            let mylocationCamera = GMSCameraPosition.camera(
                withLatitude: mylocation.coordinate.latitude,
                longitude: mylocation.coordinate.longitude,
                zoom: 15
            )
            self.mapView.animate(to: mylocationCamera)
        } else {
            print("User's location is unknown")
        }
    }

    @objc func goToDefaultLocation() {
        self.mapView.animate(to: camera)
    }

    @objc func changeIndex(sender: UIButton?) {
        if let tag = sender?.tag {
            print(tag, AirIndexTypes.allCases[tag])
            self.airIndexTypeSelected = AirIndexTypes.allCases[tag]

            for button in indexSelectorView.buttons {
                button.setTitleColor(button.tag == tag ? UIColor(rgb: 0x5AC8FA) : .label, for: .normal)
            }
        }
    }

    @objc func dismissModal() {
        self.dismiss(animated: true, completion: nil)
    }

    var isWindMode = false {
        didSet {
            functionalButtonsView.windModeButton.tintColor = isWindMode ? .white : .label
            functionalButtonsView.windModeButton.backgroundColor = isWindMode ? UIColor(rgb: 0x5AC8FA) : .tertiarySystemBackground
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

        // TODO: move to auto-layout
        let hasNotch = UIDevice.current.hasNotch

        // MARK: closestStationView
        var positionY: CGFloat = isLandscape ? 20 : 50
        positionY = hasNotch ? positionY : positionY - 30
        closestStationView = ClosestStationView(frame: CGRect(
            x: isLandscape ? 55 : 20,
            y: positionY,
            width: 200,
            height: 75
        ))
        view.addSubview(closestStationView)

        // MARK: airStatusesView
        positionY = isLandscape ? 100 : 130
        positionY = hasNotch ? positionY : positionY - 30
        let airStatusesView = AirStatusBarView(frame: CGRect(
            x: isLandscape ? 55 : 20,
            y: positionY,
            width: 200,
            height: 32
        ))
        view.addSubview(airStatusesView)

        let isPro = defaults.bool(forKey: "pro")
        let airIndexTypeSelected = defaults.string(forKey: "airIndexTypeSelected")
            .flatMap { AirIndexTypes(rawValue: $0) } ?? .aqi

        // MARK: functionalButtonsView
        positionY = isLandscape ? height - 300 : height - 345
        positionY = hasNotch ? positionY : positionY + 40
        functionalButtonsView = FunctionalButtonsView(frame: CGRect(
            x: isLandscape ? 55 : 15,
            y: isPro ? positionY + 50 : positionY,
            width: isLandscape ? width - 115 : width - 30,
            height: isLandscape ? 125 : 135
        ))
        functionalButtonsView.defaultLocationButton.addTarget(self, action: #selector(goToDefaultLocation), for: .touchUpInside)
        functionalButtonsView.myLocationButton.addTarget(self, action: #selector(goToMyLocation), for: .touchUpInside)
        functionalButtonsView.windModeButton.tintColor = isWindMode ? .white : .label
        functionalButtonsView.windModeButton.backgroundColor = isWindMode ? UIColor(rgb: 0x5AC8FA) : .tertiarySystemBackground
        functionalButtonsView.windModeButton.addTarget(self, action: #selector(toggleIsWindMode), for: .touchUpInside)
        view.addSubview(functionalButtonsView)

        // MARK: indexSelectorView
        positionY = isLandscape ? height - 173 : height - 195
        positionY = hasNotch ? positionY : positionY + 40
        if width > 800 {
            indexSelectorView = IndexSelectorView(frame: CGRect(
                x: isLandscape ? 40 : 0,
                y: isPro ? positionY + 50 : positionY,
                width: 620,
                height: 50
            ))
            indexSelectorView.center.x = width / 2
        } else {
            indexSelectorView = IndexSelectorView(frame: CGRect(
                x: isLandscape ? 40 : 0,
                y: isPro ? positionY + 50 : positionY,
                width: width,
                height: 50
            ))
        }
        for (i, airIndexType) in AirIndexTypes.allCases.enumerated() {
            indexSelectorView.buttons[i].addTarget(self, action: #selector(changeIndex), for: .touchUpInside)

            if airIndexTypeSelected == airIndexType {
                indexSelectorView.buttons[i].setTitleColor(UIColor(rgb: 0x5AC8FA), for: .normal)
            }
        }
        view.addSubview(indexSelectorView)

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

            closestStationView.stationName = "\(closestPollutant.siteName), \(closestPollutant.county)"
            closestStationView.status = closestPollutant.status
            closestStationView.aqi = "AQI \(closestPollutant.aqi)"
            let airStatus = AirStatuses.checkAirStatus(
                airIndexType: AirIndexTypes.aqi,
                value: Double(closestPollutant.aqi) ?? 0
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
            self.goToMyLocation()
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
