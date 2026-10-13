import Foundation

/// A camera's recording area (the part of the sensor that makes the picture), in millimetres.
public struct CameraFormat: Identifiable, Equatable, Hashable, Codable {
    public var id: String
    public var name: String
    public var widthMM: Double
    public var heightMM: Double
    public var isCustom: Bool

    public init(id: String, name: String, widthMM: Double, heightMM: Double, isCustom: Bool = false) {
        self.id = id; self.name = name; self.widthMM = widthMM; self.heightMM = heightMM; self.isCustom = isCustom
    }

    public var diagonalMM: Double { (widthMM * widthMM + heightMM * heightMM).squareRoot() }
}

/// A frame shape (aspect ratio) cut out of the recording area. `ratio` is width / height; nil = the whole recording area.
public struct AspectOption: Identifiable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let ratio: Double?

    public init(id: String, name: String, ratio: Double?) {
        self.id = id; self.name = name; self.ratio = ratio
    }
}

/// An ND filter strength.
public struct NDFilter: Identifiable, Equatable, Hashable {
    public let stops: Double
    public init(stops: Double) { self.stops = stops }
    public var id: Double { stops }
    /// Optical density: 0.3 per stop
    public var density: Double { stops * 0.3 }
    public var label: String { stops == 0 ? "Clear" : "ND " + String(format: "%.1f", density) }
}

/// Built-in cameras, lenses, frame shapes and settings. The recording areas are approximate and vary by recording
/// mode, so the app also lets you enter your own.
public enum Gear {
    public static let cameras: [CameraFormat] = [
        CameraFormat(id: "ff-3x2", name: "Full frame 36 × 24 (3:2)", widthMM: 36.0, heightMM: 24.0),
        CameraFormat(id: "ff-16x9", name: "Full frame 16:9 (FX3, A7S III, R5 C)", widthMM: 35.6, heightMM: 20.0),
        CameraFormat(id: "alexa-mini-lf", name: "ARRI ALEXA Mini LF (open gate)", widthMM: 36.70, heightMM: 25.54),
        CameraFormat(id: "alexa-35", name: "ARRI ALEXA 35 (open gate)", widthMM: 27.99, heightMM: 19.22),
        CameraFormat(id: "alexa-mini", name: "ARRI ALEXA Mini (S35 open gate)", widthMM: 28.25, heightMM: 18.17),
        CameraFormat(id: "red-vraptor", name: "RED V-RAPTOR 8K VV", widthMM: 40.96, heightMM: 21.60),
        CameraFormat(id: "red-komodo", name: "RED KOMODO 6K", widthMM: 27.03, heightMM: 14.26),
        CameraFormat(id: "venice-2", name: "Sony VENICE 2 (8.6K)", widthMM: 36.2, heightMM: 24.1),
        CameraFormat(id: "s35-16x9", name: "Super 35 (16:9)", widthMM: 24.89, heightMM: 14.00),
        CameraFormat(id: "s35-academy", name: "Super 35 film (Academy)", widthMM: 22.0, heightMM: 16.0),
        CameraFormat(id: "canon-c70", name: "Canon C70 / C300 III (S35)", widthMM: 26.2, heightMM: 13.8),
        CameraFormat(id: "bmpcc-6k", name: "Blackmagic Pocket 6K", widthMM: 23.1, heightMM: 12.99),
        CameraFormat(id: "bmpcc-4k", name: "Blackmagic Pocket 4K", widthMM: 18.96, heightMM: 10.0),
        CameraFormat(id: "mft-16x9", name: "Micro Four Thirds (16:9)", widthMM: 17.3, heightMM: 9.7),
        CameraFormat(id: "aps-c", name: "APS-C (3:2)", widthMM: 23.5, heightMM: 15.6),
        CameraFormat(id: "one-inch", name: "1-inch (3:2)", widthMM: 13.2, heightMM: 8.8),
        CameraFormat(id: "super-16", name: "Super 16 film", widthMM: 12.52, heightMM: 7.41),
        CameraFormat(id: "gfx", name: "Medium format GFX (4:3)", widthMM: 43.8, heightMM: 32.9)
    ]

    public static let defaultCameraID = "alexa-mini"

    public static let focalLengths: [Double] = [8, 10, 12, 14, 16, 18, 21, 24, 25, 28, 32, 35, 40, 50, 65, 75, 85, 100, 135, 150, 200, 300]

    public static let aspects: [AspectOption] = [
        AspectOption(id: "native", name: "Full sensor", ratio: nil),
        AspectOption(id: "16x9", name: "16:9", ratio: 16.0 / 9.0),
        AspectOption(id: "1.85", name: "1.85:1", ratio: 1.85),
        AspectOption(id: "2.0", name: "2:1", ratio: 2.0),
        AspectOption(id: "2.35", name: "2.35:1", ratio: 2.35),
        AspectOption(id: "2.39", name: "2.39:1", ratio: 2.39),
        AspectOption(id: "4x3", name: "4:3", ratio: 4.0 / 3.0),
        AspectOption(id: "1x1", name: "1:1", ratio: 1.0),
        AspectOption(id: "4x5", name: "4:5", ratio: 0.8),
        AspectOption(id: "9x16", name: "9:16", ratio: 9.0 / 16.0)
    ]

    public static let framesPerSecond: [Double] = [23.976, 24, 25, 29.97, 30, 48, 50, 59.94, 60, 120]
    public static let shutterAngles: [Double] = [45, 90, 144, 172.8, 180, 270, 360]
    public static let isos: [Double] = [100, 160, 200, 400, 640, 800, 1250, 1600, 3200, 6400]
    public static let fStops: [Double] = [1.2, 1.4, 1.8, 2, 2.8, 4, 5.6, 8, 11, 16, 22]

    /// Common ND filters, 0 to 10 stops, plus a few heavier ones.
    public static let ndFilters: [NDFilter] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15].map { NDFilter(stops: Double($0)) }

    public static func fpsLabel(_ fps: Double) -> String {
        fps == fps.rounded() ? String(Int(fps)) : String(format: "%.3g", fps)
    }

    public static func angleLabel(_ angle: Double) -> String {
        (angle == angle.rounded() ? String(Int(angle)) : String(format: "%.1f", angle)) + "°"
    }

    public static func focalLabel(_ mm: Double) -> String {
        (mm == mm.rounded() ? String(Int(mm)) : String(format: "%.1f", mm)) + "mm"
    }
}
