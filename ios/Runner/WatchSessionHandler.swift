import Foundation
import WatchConnectivity
import Flutter

@objc class WatchSessionHandler: NSObject, FlutterStreamHandler, WCSessionDelegate {
  static let shared = WatchSessionHandler()

  private var session: WCSession?
  private var sink: FlutterEventSink?

  private override init() {
    super.init()
    if WCSession.isSupported() {
      session = WCSession.default
      session?.delegate = self
    }
  }

  func activate() {
    session?.activate()
  }

  // MARK: - FlutterStreamHandler
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    activate()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  // MARK: - WCSessionDelegate
  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    // no-op
  }

  func sessionDidBecomeInactive(_ session: WCSession) {
    // no-op
  }

  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }

  func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
    DispatchQueue.main.async { [weak self] in
      guard let sink = self?.sink else { return }
      sink(message)
    }
  }

  // For background transfers or applicationContext updates you can implement more delegates.
}
