import Foundation
import CoreMotion
import WatchConnectivity
import Combine

final class MotionManager: NSObject, ObservableObject {
    static let shared = MotionManager()

    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()

    @Published var ax: Double = 0
    @Published var ay: Double = 0
    @Published var az: Double = 0

    @Published var gx: Double = 0
    @Published var gy: Double = 0
    @Published var gz: Double = 0

    @Published var pitch: Double = 0
    @Published var roll: Double = 0
    @Published var yaw: Double = 0

    @Published var isRunning: Bool = false

    func start() {
        guard !isRunning else { return }
        guard motionManager.isDeviceMotionAvailable else {
            print("Device motion not available")
            return
        }

        isRunning = true
        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0

        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
            guard let self, let motion = motion else {
                if let error = error {
                    print("Motion error: \(error.localizedDescription)")
                }
                return
            }

            DispatchQueue.main.async {
                self.ax = motion.userAcceleration.x
                self.ay = motion.userAcceleration.y
                self.az = motion.userAcceleration.z

                self.gx = motion.rotationRate.x
                self.gy = motion.rotationRate.y
                self.gz = motion.rotationRate.z

                self.pitch = motion.attitude.pitch
                self.roll = motion.attitude.roll
                self.yaw = motion.attitude.yaw
            }

            self.sendToPhone(motion: motion)
        }
    }

    func stop() {
        isRunning = false
        motionManager.stopDeviceMotionUpdates()
    }

    private func sendToPhone(motion: CMDeviceMotion) {
        guard WCSession.default.activationState == .activated else { return }
        guard WCSession.default.isReachable else { return }

        let payload: [String: Any] = [
            "ax": motion.userAcceleration.x,
            "ay": motion.userAcceleration.y,
            "az": motion.userAcceleration.z,
            "gx": motion.rotationRate.x,
            "gy": motion.rotationRate.y,
            "gz": motion.rotationRate.z,
            "pitch": motion.attitude.pitch,
            "roll": motion.attitude.roll,
            "yaw": motion.attitude.yaw,
            "ts": Date().timeIntervalSince1970
        ]

        WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: { error in
            print("sendMessage error: \(error.localizedDescription)")
        })
    }
}
