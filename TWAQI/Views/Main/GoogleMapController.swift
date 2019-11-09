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

    var windModeButton: UIButton!
    var myLocationButton: UIButton!
    var defaultLocationButton: UIButton!
    var closestStationView: ClosestStationView!

    var scrollView: UIScrollView!
    var buttons: [UIButton] = []

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
            self.selectedIndex = AirIndexTypes.allCases[tag]

            for button in buttons {
                button.setTitleColor(button.tag == tag ? UIColor(rgb: 0x5AC8FA) : .black, for: .normal)
            }
        }
    }

    @objc func dismissModal() {
        self.dismiss(animated: true, completion: nil)
    }

    var isWindMode = false {
        didSet {
            windModeButton.tintColor = isWindMode ? .white : .black
            windModeButton.backgroundColor = isWindMode ? UIColor(rgb: 0x5AC8FA) : .white
            update()
        }
    }

    var selectedIndex: AirIndexTypes = AirIndexTypes.aqi {
        didSet {
            update()
        }
    }

    func update() {
        self.mapView.clear()
        self.pollutants.forEach { pollutant in
            var pollutantMarker: GMSMarker
            if self.isWindMode {
                pollutantMarker = WindDirectionMarker(pollutant: pollutant, selectedIndex: self.selectedIndex)
            } else {
                pollutantMarker = PollutantMarker(pollutant: pollutant, selectedIndex: self.selectedIndex)
            }
            pollutantMarker.map = self.mapView
        }
    }

    func loadContent(
        width: CGFloat = screenSize.width,
        height: CGFloat = screenSize.height,
        isLandscape: Bool = UIDevice.current.orientation.isLandscape
    ) {
        mapView.frame = CGRect(x: 0, y: 0, width: width, height: height)

        let view = UIView()
        view.backgroundColor = .white
        view.addSubview(mapView)

        // Wind button
        windModeButton = UIButton(frame: CGRect(x: isLandscape ? 55 : 15, y: isLandscape ? height - 250 : height - 270, width: 60, height: 60))
        let windModeIcon = UIImage(systemName: "wind")
        windModeButton.setImage(windModeIcon, for: .normal)
        windModeButton.tintColor = isWindMode ? .white : .black
        windModeButton.backgroundColor = isWindMode ? UIColor(rgb: 0x5AC8FA) : .white
        windModeButton.layer.cornerRadius = 30
        windModeButton.layer.shadowColor = UIColor.black.cgColor
        windModeButton.layer.shadowOffset = CGSize(width: 0.0, height: 3.0)
        windModeButton.layer.shadowRadius = 2
        windModeButton.layer.shadowOpacity = 0.1
        windModeButton.addTarget(self, action: #selector(toggleIsWindMode), for: .touchUpInside)
        view.addSubview(windModeButton)

        // My location button
        myLocationButton = UIButton(frame: CGRect(
            x: isLandscape ? width - 115 : width - 75,
            y: isLandscape ? height - 250 : height - 270,
            width: 60,
            height: 60
        ))
        let myLocationIcon = UIImage(systemName: "paperplane.fill")
        myLocationButton.setImage(myLocationIcon, for: .normal)
        myLocationButton.tintColor = UIColor(rgb: 0x5AC8FA)
        myLocationButton.backgroundColor = .white
        myLocationButton.layer.cornerRadius = 30
        myLocationButton.layer.shadowColor = UIColor.black.cgColor
        myLocationButton.layer.shadowOffset = CGSize(width: 0.0, height: 3.0)
        myLocationButton.layer.shadowRadius = 2
        myLocationButton.layer.shadowOpacity = 0.1
        myLocationButton.addTarget(self, action: #selector(goToMyLocation), for: .touchUpInside)
        view.addSubview(myLocationButton)

        // Default location button
        defaultLocationButton = UIButton(frame: CGRect(
            x: isLandscape ? width - 115 : width  - 75,
            y: isLandscape ? height - 320 : height - 340,
            width: 60,
            height: 60
        ))
        let defaultLocationIcon = UIImage(systemName: "viewfinder")
        defaultLocationButton.setImage(defaultLocationIcon, for: .normal)
        defaultLocationButton.tintColor = UIColor(rgb: 0x5AC8FA)
        defaultLocationButton.backgroundColor = .white
        defaultLocationButton.layer.cornerRadius = 30
        defaultLocationButton.layer.shadowColor = UIColor.black.cgColor
        defaultLocationButton.layer.shadowOffset = CGSize(width: 0.0, height: 3.0)
        defaultLocationButton.layer.shadowRadius = 2
        defaultLocationButton.layer.shadowOpacity = 0.1
        defaultLocationButton.addTarget(self, action: #selector(goToDefaultLocation), for: .touchUpInside)
        view.addSubview(defaultLocationButton)

        let indexButton = UIButton()
        indexButton.setImage(defaultLocationIcon, for: .normal)
        indexButton.tintColor = UIColor(rgb: 0x5AC8FA)
        indexButton.backgroundColor = .white
        indexButton.layer.cornerRadius = 30
        indexButton.layer.shadowColor = UIColor.black.cgColor
        indexButton.layer.shadowOffset = CGSize(width: 0.0, height: 3.0)
        indexButton.layer.shadowRadius = 2
        indexButton.layer.shadowOpacity = 0.1
        indexButton.addTarget(self, action: #selector(goToDefaultLocation), for: .touchUpInside)

        scrollView = UIScrollView(frame: CGRect(
            x: isLandscape ? 40 : 0, 
            y: isLandscape ? height - 175 : height - 195, 
            width: width, 
            height: 60
        ))
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false

        let buttonPadding: CGFloat = 10
        var xOffset: CGFloat = 15

        for (i, airIndexType) in AirIndexTypes.allCases.enumerated() {
            let button = UIButton()
            buttons.append(button)
            button.tag = i
            button.setTitle(airIndexType.toString(), for: .normal)
            button.setTitleColor(selectedIndex == airIndexType ? UIColor(rgb: 0x5AC8FA) : .black, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14)
            button.backgroundColor = .white
            button.layer.cornerRadius = 25
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOffset = CGSize(width: 0.0, height: 3.0)
            button.layer.shadowRadius = 2
            button.layer.shadowOpacity = 0.1
            button.addTarget(self, action: #selector(changeIndex), for: .touchUpInside)

            button.frame = CGRect(x: xOffset, y: 0, width: 75, height: 50)
            xOffset += CGFloat(buttonPadding) + button.frame.size.width

            scrollView.addSubview(button)
        }

        scrollView.contentSize = CGSize(width: xOffset, height: scrollView.frame.height)
        view.addSubview(scrollView)

        // MARK: closestStationView
        closestStationView = ClosestStationView(frame: CGRect(
            x: isLandscape ? 55 : 20,
            y: isLandscape ? 15 : 50,
            width: 200,
            height: 75
        ))
        view.addSubview(closestStationView)

        // MARK: airStatusesView
        let airStatusesView = AirStatusBarView(frame: CGRect(
            x: isLandscape ? 55 : 20,
            y: isLandscape ? 95 : 130,
            width: 200,
            height: 32
        ))
        view.addSubview(airStatusesView)

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

        loadContent()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        if UIDevice.current.orientation.isLandscape {
            print("Landscape", size.width, UIDevice.current.orientation, screenSize)
            self.loadContent(width: size.width, height: size.height, isLandscape: true)
        } else {
            print("Portrait", size, UIDevice.current.orientation, screenSize)
            self.loadContent(width: size.width, height: size.height, isLandscape: false)
        }
        update()
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
