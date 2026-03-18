import WatchKit
import Foundation
import WatchConnectivity
import CoreMotion

class InterfaceController: WKInterfaceController, WCSessionDelegate {
    let motionManager = CMMotionManager()
    var session: WCSession?

    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    override func willActivate() {
        super.willActivate()
        startMotionUpdates()
    }

    override func didDeactivate() {
        super.didDeactivate()
        stopMotionUpdates()
    }

    func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
        motionManager.startDeviceMotionUpdates(to: OperationQueue()) { [weak self] motion, error in
            guard let motion = motion else { return }
            let imu: [String: Any] = [
                "timestamp": Date().timeIntervalSince1970,
                "accel": [motion.userAcceleration.x, motion.userAcceleration.y, motion.userAcceleration.z],
                "gyro": [motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z]
            ]
            if let session = self?.session, session.isReachable {
                session.sendMessage(["imu": imu], replyHandler: nil, errorHandler: nil)
            } else {
                // Optionally updateApplicationContext
                try? self?.session?.updateApplicationContext(["imu": imu])
            }
        }
    }

    func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }

    // MARK: - WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { }
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) { }
}
