import Flutter

/// Shared singleton that bridges the `analysis_progress` EventChannel to Swift callers.
/// Any processing pipeline (pose, trimmer, etc.) calls `send(...)` to push progress to Dart.
final class AnalysisProgressSink: NSObject, FlutterStreamHandler {
  static let shared = AnalysisProgressSink()

  private var eventSink: FlutterEventSink?
  private let lock = NSLock()

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    lock.lock(); defer { lock.unlock() }
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    lock.lock(); defer { lock.unlock() }
    eventSink = nil
    return nil
  }

  func send(op: String, progress: Double, label: String, current: Int = 0, total: Int = 0) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?([
        "op": op,
        "progress": progress,
        "label": label,
        "current": current,
        "total": total,
      ] as [String: Any])
    }
  }
}
