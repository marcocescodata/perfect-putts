// Streams AirPods motion as one JSON object per line on stdout, for the Python side to read.
// macOS only lets binaries with an NSMotionUsageDescription read motion, which a python
// interpreter can't have — so this tiny helper does the sensor part and nothing else.
import CoreMotion
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
let manager = CMHeadphoneMotionManager()

func emit(_ object: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: object),
       let line = String(data: data, encoding: .utf8) {
        print(line)
    }
}

final class Delegate: NSObject, CMHeadphoneMotionManagerDelegate {
    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) { emit(["event": "connected"]) }
    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) { emit(["event": "disconnected"]) }
}
let delegate = Delegate()
manager.delegate = delegate

guard manager.isDeviceMotionAvailable else {
    emit(["event": "error", "message": "headphone motion unavailable"])
    exit(1)
}
emit(["event": "started", "auth": CMHeadphoneMotionManager.authorizationStatus().rawValue])

manager.startDeviceMotionUpdates(to: .main) { motion, error in
    if let error {
        emit(["event": "error", "message": error.localizedDescription])
        return
    }
    guard let m = motion else { return }
    emit([
        "t": m.timestamp,
        "gx": m.rotationRate.x, "gy": m.rotationRate.y, "gz": m.rotationRate.z,
        "ax": m.userAcceleration.x, "ay": m.userAcceleration.y, "az": m.userAcceleration.z,
    ])
}
RunLoop.main.run()
