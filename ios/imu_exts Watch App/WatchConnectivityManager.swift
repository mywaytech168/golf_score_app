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

    // MARK: - WCSessionDelegate 必要方法

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        print("Watch WCSession activated: \(activationState.rawValue), error: \(String(describing: error))")
    }

    // iOS 上需要這兩個方法，watchOS 不需要但加上也無妨
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("WCSession did become inactive")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        print("WCSession did deactivate")
        session.activate()
    }
    #endif

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

    // 接收帶回覆的訊息
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        if let command = message["command"] as? String {
            DispatchQueue.main.async {
                switch command {
                case "start":
                    print("Watch: Received start command (with reply)")
                    MotionManager.shared.start()
                    replyHandler(["status": "started"])
                case "stop":
                    print("Watch: Received stop command (with reply)")
                    MotionManager.shared.stop()
                    replyHandler(["status": "stopped"])
                default:
                    replyHandler(["status": "unknown"])
                }
            }
        } else {
            replyHandler(["status": "no command"])
        }
    }
}
