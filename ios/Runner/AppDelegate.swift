import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // 取得根視圖控制器並建立螢幕常亮的 MethodChannel
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "keep_screen_on_channel",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "enable":
          // 停用 iOS 休眠計時，確保錄影期間螢幕保持亮起
          UIApplication.shared.isIdleTimerDisabled = true
          result(nil)
        case "disable":
          // 恢復預設休眠邏輯，避免離開錄影頁後仍持續常亮
          UIApplication.shared.isIdleTimerDisabled = false
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
