import Flutter
import Photos
import UIKit

// MARK: - Helpers

/// 取得目前前景 active scene 的 key window 的 rootViewController。
/// 取代已於 iOS 15 deprecated 的 `UIApplication.shared.windows`，且在多場景下能正確選中前景視窗。
private func vxRootViewController() -> UIViewController? {
  let scenes = UIApplication.shared.connectedScenes
    .compactMap { $0 as? UIWindowScene }
  // 優先前景 active scene，退而求其次任一 scene
  let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
  let keyWindow = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
  return keyWindow?.rootViewController
}

// MARK: - Registration

func registerVideoExportChannel(messenger: FlutterBinaryMessenger) {
  FlutterMethodChannel(
    name: "com.example.golf_score_app/video_export",
    binaryMessenger: messenger
  ).setMethodCallHandler { call, result in
    guard let args    = call.arguments as? [String: Any],
          let srcPath = args["srcPath"] as? String,
          !srcPath.isEmpty
    else {
      result(FlutterMethodNotImplemented)
      return
    }

    switch call.method {
    case "saveToDownloads":
      // iOS: 儲存到相機膠卷（Photos library）
      // 等同 Android「下載」體驗，使用者可在「照片」App 中找到影片
      vxSaveVideoToPhotos(srcPath: srcPath, result: result)

    case "pickFolderAndSave":
      // iOS: 等同 Android SAF —— Document Picker 匯出到「檔案」App 任選位置
      let fileName = args["fileName"] as? String ?? URL(fileURLWithPath: srcPath).lastPathComponent
      vxPickFolderAndSave(srcPath: srcPath, fileName: fileName, result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

// MARK: - Pick folder and save (Document Picker, mirrors Android ACTION_OPEN_DOCUMENT_TREE)

/// Document Picker 的 delegate 需在 picker 存活期間被持有
private var vxActivePickerDelegate: VxDocumentPickerDelegate?

private final class VxDocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
  private let result: FlutterResult
  private let tempURL: URL

  init(result: @escaping FlutterResult, tempURL: URL) {
    self.result = result
    self.tempURL = tempURL
  }

  func documentPicker(_ controller: UIDocumentPickerViewController,
                      didPickDocumentsAt urls: [URL]) {
    try? FileManager.default.removeItem(at: tempURL)
    result(urls.first?.path ?? "")
    vxActivePickerDelegate = nil
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    try? FileManager.default.removeItem(at: tempURL)
    result(FlutterError(code: "cancelled", message: "使用者取消選擇", details: nil))
    vxActivePickerDelegate = nil
  }
}

private func vxPickFolderAndSave(srcPath: String, fileName: String, result: @escaping FlutterResult) {
  guard FileManager.default.fileExists(atPath: srcPath) else {
    result(FlutterError(code: "file_not_found", message: "影片檔案不存在: \(srcPath)", details: nil))
    return
  }

  // 先複製到暫存檔，讓匯出的檔名 = 使用者指定的 fileName
  let tempURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    .appendingPathComponent(fileName)
  do {
    try? FileManager.default.removeItem(at: tempURL)
    try FileManager.default.copyItem(at: URL(fileURLWithPath: srcPath), to: tempURL)
  } catch {
    result(FlutterError(code: "save_failed", message: error.localizedDescription, details: nil))
    return
  }

  DispatchQueue.main.async {
    guard let rootVC = vxRootViewController() else {
      try? FileManager.default.removeItem(at: tempURL)
      result(FlutterError(code: "no_view_controller", message: "找不到 rootViewController", details: nil))
      return
    }

    let picker: UIDocumentPickerViewController
    if #available(iOS 14, *) {
      picker = UIDocumentPickerViewController(forExporting: [tempURL], asCopy: true)
    } else {
      picker = UIDocumentPickerViewController(url: tempURL, in: .exportToService)
    }
    let delegate = VxDocumentPickerDelegate(result: result, tempURL: tempURL)
    vxActivePickerDelegate = delegate
    picker.delegate = delegate
    rootVC.present(picker, animated: true)
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
  guard let rootVC = vxRootViewController() else {
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
