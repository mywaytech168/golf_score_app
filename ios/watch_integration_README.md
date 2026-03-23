# Apple Watch IMU Integration (模板 & 步驟)

以下為將 Apple Watch 連線並傳送 IMU 資料到 iOS / Flutter 的範例模板與整合步驟。這些檔案為範例，請在 Xcode 中把 watch target 與檔案正確加入到專案中。

檔案位置與說明：
- `ios/WatchExtension/InterfaceController.swift`：watchOS 端範例，使用 `CMMotionManager` 取得 DeviceMotion，並透過 `WCSession.sendMessage` 傳送 `{"imu": {...}}`。
- `ios/Runner/WatchSessionHandler.swift`：iOS 端接收器，實作 `WCSessionDelegate` 並將收到的 message 透過 Flutter `EventChannel` 轉發給 Flutter。
- `lib/watch_imu.dart`：Flutter 端小封裝，提供 `imuStream` 接收從手錶傳來的資料。

整合步驟（概要）：
1. 在 Xcode 中為 iOS App 新增一個 Watch App target（含 WatchKit Extension）。
2. 將 `InterfaceController.swift` 加入到 WatchKit Extension 目標中（`WatchExtension` target）。
3. 將 `WatchSessionHandler.swift` 加入到 iOS `Runner` target。App 启动时已在 `AppDelegate.swift` 註冊 EventChannel（`watch_imu_stream`）。
4. 確認 `WatchConnectivity` 在 iOS 與 watchOS 端都已啟用（預設應可用）。
5. 在 Flutter 端使用 `WatchImu().imuStream.listen((data) { ... })` 接收資料。

注意事項：
- `WCSession.sendMessage` 只會在裝置彼此 reachable（主 App 在前台或手錶可達）時即時送達；否則可改用 `updateApplicationContext` 作背景同步。
- 若要長時間在背景蒐集 IMU 資料，需依 Apple 的限制與使用情境評估是否允許。手錶可能需要適當的電源與隱私說明。
- 這些範例不包含完整錯誤處理、權限提示或 power/性能最佳化，建議在上線前補齊。

範例 Flutter 使用：
```dart
import 'package:your_app/watch_imu.dart';

void listen() {
  WatchImu().imuStream.listen((data) {
    print('IMU from watch: $data');
  });
}
```
