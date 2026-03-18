import Foundation
import WatchConnectivity

final class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        print("Watch WCSession activated: \(activationState.rawValue), error: \(String(describing: error))")
    }

    // 接收來自 iPhone 的指令
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if let command = message["command"] as? String {
            DispatchQueue.main.async {
                switch command {
                case "start":
                    print("Watch: Received start command")
                    MotionManager.shared.start()
                case "stop":
                    print("Watch: Received stop command")
                    MotionManager.shared.stop()
                default:
                    break
                }
            }
        }
    }
}
