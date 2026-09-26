import Foundation

public struct Vector3: Sendable, Codable, Equatable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vector3(x: 0, y: 0, z: 0)

    public var length: Double { (x * x + y * y + z * z).squareRoot() }

    public var normalized: Vector3 {
        let l = length
        return l > 0 ? self * (1 / l) : .zero
    }

    public func dot(_ o: Vector3) -> Double { x * o.x + y * o.y + z * o.z }

    public static func + (a: Vector3, b: Vector3) -> Vector3 { Vector3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
    public static func - (a: Vector3, b: Vector3) -> Vector3 { Vector3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
    public static func * (a: Vector3, s: Double) -> Vector3 { Vector3(x: a.x * s, y: a.y * s, z: a.z * s) }
}

/// One reading from the headphone motion sensor.
public struct MotionSample: Sendable, Codable, Equatable {
    /// Seconds, monotonic (CMDeviceMotion.timestamp is seconds since boot).
    public var timestamp: TimeInterval
    /// Gyroscope, rad/s, in the AirPod's own reference frame.
    public var rotationRate: Vector3
    /// Acceleration minus gravity, in g.
    public var userAcceleration: Vector3

    public init(timestamp: TimeInterval, rotationRate: Vector3, userAcceleration: Vector3 = .zero) {
        self.timestamp = timestamp
        self.rotationRate = rotationRate
        self.userAcceleration = userAcceleration
    }
}
