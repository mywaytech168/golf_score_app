# 在 iPhone 上測試 IPA 檔案

下載的 `.ipa` 檔可透過 Xcode 安裝至實體裝置進行測試。

## 安裝步驟
1. 將 iPhone 透過 USB 連接至 macOS，並在手機上選擇信任此電腦。
2. 開啟 **Xcode**，在選單中點選 `Window > Devices and Simulators`。
3. 在左側選擇已連線的裝置，於右側點擊 **Add** 按鈕或拖曳 `.ipa` 至裝置視窗。
4. 等待安裝完成後，於 iPhone 主畫面即可看到應用程式圖示。
5. 若首次安裝需信任開發者，可在 `設定 > 一般 > 裝置管理` 中完成信任。

## 其他測試方式
若需提供多位測試者使用，可將 `.ipa` 上傳至 **TestFlight**，並透過 App Store Connect 發送測試邀請。
