import CoreLocation
import Foundation

/// One-shot "where am I" for the sun times.
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var message = "Tap the button to get today's sunrise, golden hour, and sunset for where you are."

    private let manager = CLLocationManager()
    private var wantsLocation = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func request() {
        wantsLocation = true
        message = "Finding your location…"
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            message = "Couldn't get your location. Allow location access for TempScout in Settings and try again."
        default:
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard wantsLocation else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            message = "Couldn't get your location. Allow location access for TempScout in Settings and try again."
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        coordinate = c
        message = String(format: "For %.2f, %.2f · ", c.latitude, c.longitude) + Date().formatted(date: .abbreviated, time: .omitted)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        message = "Couldn't get your location. Try again."
    }
}
