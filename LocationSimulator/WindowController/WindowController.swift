//
//  WindowController.swift
//  LocationSimulator
//
//  Created by David Klopp on 18.08.19.
//  Copyright © 2019 David Klopp. All rights reserved.
//

import Foundation
import AppKit
import MapKit
import CoreLocation
import GPXParser
import LocationSpoofer

/// The main window controller instance which hosts the map view and the toolbar.
class WindowController: NSWindowController {
    // MARK: - Enums

    enum RotateDirection {
        case clockwise
        case counterclockwise
    }

    enum MoveDirection {
        case up
        case down
        case left
        case right
    }

    // MARK: - Controller / Model

    /// The toolbar controller instance to handle the toolbar validation as well as the toolbar actions.
    @IBOutlet var toolbarController: ToolbarController!

    /// The touchbar controller instance to handle the touchbar validation as well as the touchbar actions.
    @IBOutlet var touchbarController: TouchbarController!

    // MARK: - ViewController

    /// Reference to the SplitViewController
    public var splitViewController: SplitViewController? {
        return self.contentViewController as? SplitViewController
    }

    /// Reference to the mapViewController if one exists.
    public var mapViewController: MapViewController? {
        return self.splitViewController?.detailViewController as? MapViewController
    }

    // MARK: - Model

    /// Internal reference to a location manager for this mac's location
    private let locationManager = CLLocationManager()

    /// The device status observer used to update toolbar and touchbar.
    private var statusObserver: NSObjectProtocol?

    // MARK: - Helper

    public var moveType: MoveType {
        guard self.toolbarController.moveType == self.touchbarController.moveType else {
            fatalError("Inconsistent moveType status between touchbar and toolbar!")
        }
        return self.toolbarController.moveType
    }

    public var speed: Double {
        return self.toolbarController.speed
    }

    // MARK: - Window lifecycle

    override func windowDidLoad() {
        super.windowDidLoad()

        // Set the default move type
        self.setMoveType(.walk)

        // Disable the touchbar and toolbar.
        self.toolbarController.updateForDeviceStatus(.disconnected)
        self.touchbarController.updateForDeviceStatus(.disconnected)

        // Request the permission to access the mac's location.
        // Otherwise the current location button won't work.
        if #available(OSX 10.15, *) {
            self.locationManager.requestAlwaysAuthorization()
        }
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest

        // Listen for state changes to update the toolbar and touchbar.
        self.statusObserver = NotificationCenter.default.addObserver(forName: .StatusChanged, object: nil,
                                                                     queue: .main) { [weak self] notification in
            // Make sure the event belongs to this window (might be useful for multiple windows in the future).
            guard let viewController = notification.object as? NSViewController,
                  let windowController = viewController.view.window?.windowController,
                  windowController == self,
                  let newState = notification.userInfo?["status"] as? DeviceStatus else { return }
            // Update the UI for the new status
            self?.toolbarController.updateForDeviceStatus(newState)
            self?.touchbarController.updateForDeviceStatus(newState)
        }
    }

    deinit {
        // Remove the observer
        if let observer = self.statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        self.statusObserver = nil
    }

    // MARK: - Helper

    /// Toggle the sidebar visibility.
    public func toggleSidebar() {
        self.splitViewController?.toggleSidebar()
    }

    /// Enabled / Disable the autofocus to current location feature.
    /// - Parameter enabled: enable or disable the autofocus
    public func setAutofocusEnabled(_ enabled: Bool) {
        self.mapViewController?.autofocusCurrentLocation = enabled
    }

    /// Enabled / Disable the autoreverse feature when navigating.
    /// - Parameter enabled: enable or disable the autoreverse
    public func setAutoreverseEnabled(_ enabled: Bool) {
        self.mapViewController?.autoreverseRoute = enabled
    }

    /// Reset the current location.
    public func resetLocation() {
        self.mapViewController?.resetLocation()
    }

    /// Set the currentlocation of this mac to the spoofed location.
    public func setLocationToCurrentLocation() {
        if !CLLocationManager.locationServicesEnabled() {
            // Check if location services are enabled.
            self.window?.showError("LOCATION_SERVICE_DISABLED", message: "LOCATION_SERVICE_DISABLED_MSG")
        } else if let coord = locationManager.location?.coordinate {
            self.requestLocationChange(coord: coord)
        } else {
            // Can not read the current user location.
            self.window?.showError("GET_LOCATION_ERROR", message: "GET_LOCATION_ERROR_MSG")
        }
    }

    /// Request a location change to the give coordinates. If no coordinates are specified, a coordinate selection
    /// view will be shown to the user.
    /// - Parameter coord: the new coordinates.
    public func requestLocationChange(coord: CLLocationCoordinate2D? = nil) {
        if let isShowingAlert = self.mapViewController?.isShowingAlert, isShowingAlert {
            // We can only request one location change at a time.
            NSSound.beep()
        } else {
            // Request the location change.
            self.mapViewController?.requestTeleportOrNavigation(toCoordinate: coord)
        }
    }

    /// Change the current move type.
    /// - Parameter moveType: The new move type to select.
    public func setMoveType(_ moveType: MoveType) {
        // Update the UI.
        self.toolbarController.moveType = moveType
        self.touchbarController.moveType = moveType
        // Update the actual move type.
        self.mapViewController?.moveType = moveType

        // Update the menubar selection
        NavigationMenubarItem.selectMoveItem(forMoveType: moveType)

        // Change the speed to the default speed value for this move type
        self.mapViewController?.speed = moveType.speed
    }

    /// Change the current movement speed.
    /// - Parameter speed: new speed value in m/s
    public func setSpeed(_ speed: Double) {
        self.mapViewController?.speed = speed
    }

    /// Toggle between the automove and the manual move state. If a navigation is running, it will be paused / resumed.
    public func toggleAutoMove() {
        self.mapViewController?.toggleAutoMove()
    }

    /// Stop the current navigation.
    public func stopNavigation() {
        self.mapViewController?.stopNavigation()
    }

    /// Move the spoofed location using the traditional behaviour.
    /// - Parameter direction: up or down
    public func moveTraditional(_ direction: MoveDirection) {
        guard let angle = self.mapViewController?.getDirectionViewAngle() else { return }
        switch direction {
        //    |                 x | x      x | x               x | x
        // ---|--- ==========> ---|--- or ---|--- ==========> ---|---
        //  x | x   arrow up      |          |     arrow up      |
        case .up:   self.mapViewController?.move(flip: angle > 90 && angle < 270)
        //  x | x                 |          |                   |
        // ---|--- ==========> ---|--- or ---|--- ==========> ---|---
        //    |    arrow down   x | x      x | x  arrow down   x | x
        case .down: self.mapViewController?.move(flip: angle < 90 || angle > 270)
        // Do nothing on left or right.
        default: break
        }
    }

    /// Move the spoofed location using the natural behaviour.
    /// - Parameter direction: up, down, left or right
    public func moveNatural(_ direction: MoveDirection) {
        switch direction {
        case .up:
            self.mapViewController?.rotateDirectionViewTo(0)
            self.mapViewController?.move(flip: false)
        case .left:
            self.mapViewController?.rotateDirectionViewTo(90)
            self.mapViewController?.move(flip: false)
        case .down:
            self.mapViewController?.rotateDirectionViewTo(180)
            self.mapViewController?.move(flip: false)
        case .right:
            self.mapViewController?.rotateDirectionViewTo(270)
            self.mapViewController?.move(flip: false)
        }
    }

    /// Rotate the direction overlay.
    /// - Parameter direction: clockwise or counterclockwise
    public func rotate(_ direction: RotateDirection) {
        switch direction {
        case .clockwise:        self.mapViewController?.rotateDirectionViewBy(-5.0)
        case .counterclockwise: self.mapViewController?.rotateDirectionViewBy(5.0)
        }
    }

    /// Return a list with all coordinates if only a signle type of points is found.
    private func uniqueCoordinates(waypoints: [WayPoint], routes: [Route],
                                   tracks: [Track]) -> [CLLocationCoordinate2D]? {
        // More than one track or route
        if tracks.count > 1 || routes.count > 1 {
            return nil
        }

        // Check if there is a single unique point collection to use
        let routepoints = routes.flatMap { $0.routepoints }
        let trackpoints = tracks.flatMap { $0.segments.flatMap { $0.trackpoints } }
        let points: [[GPXPoint]] = [waypoints, routepoints, trackpoints]
        let filteredPoints = points.filter { $0.count > 0 }

        // Return the coordinates with the unique points.
        return filteredPoints.count == 1 ? filteredPoints[0].map { $0.coordinate } : nil
    }

    /// Request to open a GPX file.
    public func requestGPXOpenDialog() {
        guard let window = self.window else { return }

        // Prepare the open file dialog
        let title = "CHOOSE_GPX_FILE"
        let (res, url): (NSApplication.ModalResponse, URL?) = window.showOpenPanel(title, extensions: ["gpx"])

        // Make sure everything is working as expected.
        guard res == .OK, let gpxFile = url else { return }
        do {
            // Try to parse the GPX file
            let parser = try GPXParser(file: gpxFile)
            parser.parse { result in
                switch result {
                case .success:
                    // Successfully opened the file
                    let waypoints = parser.waypoints
                    let routes = parser.routes
                    let tracks = parser.tracks

                    // Start the navigation of the GPX route if there is only one unique route to use.
                    if let coords = self.uniqueCoordinates(waypoints: waypoints, routes: routes, tracks: tracks) {
                        self.mapViewController?.requestGPXRouting(route: coords)
                    } else {
                        // Show a user selection window for the waypoints / routes / tracks.
                        let alert = GPXSelectionAlert(tracks: tracks, routes: routes, waypoints: waypoints)
                        alert.beginSheetModal(for: window) { response, coordinates in
                            guard response == .OK else { return }
                            self.mapViewController?.requestGPXRouting(route: coordinates)
                        }
                    }
                // Could not parse the file.
                case .failure: window.showError("ERROR_PARSE_GPX", message: "ERROR_PARSE_GPX_MSG")
                }
            }
        } catch {
            // Could not open the file.
            window.showError("ERROR_OPEN_GPX", message: "ERROR_OPEN_GPX_MSG")
        }
    }

    /// Zoom in the mapView.
    public func zoomInMap() {
        self.mapViewController?.zoomIn()
    }

    /// Zoom out the mapView.
    public func zoomOutMap() {
        self.mapViewController?.zoomOut()
    }

    /// Change the MapType of the current map.
    public func setMapType(_ mapType: MKMapType) {
        self.mapViewController?.mapType = mapType
        ViewMenubarItem.selectMapTypeItem(forMapType: mapType)
    }
}
