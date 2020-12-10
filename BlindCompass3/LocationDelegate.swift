//
//  LocationDelegate.swift
//  BlindCompass3
//
//  Created by Tony Malykh on 11/28/20.
//

import CoreLocation
import Foundation

class LocationDelegate: NSObject, CLLocationManagerDelegate {
  var locationCallback: ((CLLocation) -> ())? = nil

  var headingCallback: ((CLLocationDirection) -> ())? = nil

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let currentLocation = locations.last else { return }
    locationCallback?(currentLocation)
  }

  func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
    headingCallback?(newHeading.trueHeading)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    print("⚠️ Error while updating location " + error.localizedDescription)
  }
}
