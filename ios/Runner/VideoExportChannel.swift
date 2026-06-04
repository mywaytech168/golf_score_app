import Flutter
import Photos
import UIKit

// MARK: - Registration

func registerVideoExportChannel(messenger: FlutterBinaryMessenger) {
  FlutterMethodChannel(
    name: "com.example.golf_score_app/video_export",
    binaryMessenger: messenger
  ).setMethodCallHandler { call, result in
    guard call.method == "saveToDownloads",
          let args    = call.arguments as? [String: Any],
          let srcPath = args["srcPath"] as? String,
          !srcPath.isEmpty
    else {
      result(FlutterMethodNotImplemented)
      return
    }

    // iOS: 儲存到相機膠卷（Photos library）
    // 等同 Android「下載」體驗，使用者可在「照片」App 中找到影片
    vxSaveVideoToPhotos(srcPath: srcPath, result: result)
  }
}

// MARK: - Save to Photos library

private func vxSaveVideoToPhotos(srcPath: String, result: @escaping FlutterResult) {
  let fileURL = URL(fileURLWithPath: srcPath)
  guard FileManager.default.fileExists(atPath: srcPath) else {
    result(FlutterError(code: "file_not_found", message: "影片檔案不存在: \(srcPath)", details: nil))
    return
  }

  // 請求「加入」相簿權限（iOS 14+ 使用 .addOnly，更少侵入性）
  let requestHandler: (PHAuthorizationStatus) -> Void = { status in
    guard status == .authorized || status == .limited else {
      // 權限被拒：fallback 到 Share Sheet
      DispatchQueue.main.async {
        vxShareVideoFallback(fileURL: fileURL, result: result)
      }
      return
    }

    // 執行存入相簿
    PHPhotoLibrary.shared().performChanges({
      PHAssetCreationRequest.forAsset().addResource(
        with: .video,
        fileURL: fileURL,
        options: nil
      )
    }) { success, error in
      DispatchQueue.main.async {
        if success {
          result("saved_to_photos")
        } else {
          // 存入失敗：fallback 到 Share Sheet
          print("[VideoExport] PHPhotoLibrary 儲存失敗: \(error?.localizedDescription ?? "unknown")")
          vxShareVideoFallback(fileURL: fileURL, result: result)
        }
      }
    }
  }

  if #available(iOS 14, *) {
    PHPhotoLibrary.requestAuthorization(for: .addOnly, handler: requestHandler)
  } else {
    PHPhotoLibrary.requestAuthorization(requestHandler)
  }
}

// MARK: - Fallback: Share Sheet

private func vxShareVideoFallback(fileURL: URL, result: @escaping FlutterResult) {
  guard let rootVC = UIApplication.shared.windows.first?.rootViewController else {
    result(FlutterError(code: "no_view_controller", message: "找不到 rootViewController", details: nil))
    return
  }

  let vc = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
  // iPad support
  if let popover = vc.popoverPresentationController {
    popover.sourceView = rootVC.view
    popover.sourceRect = CGRect(
      x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY,
      width: 0, height: 0
    )
    popover.permittedArrowDirections = []
  }
  rootVC.present(vc, animated: true) {
    result("share_sheet")
  }
}
