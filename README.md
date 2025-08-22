# golf_score_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Web 版本建置

網頁端改採 Vite + Vue + Element Plus，需先安裝 Node.js 18 LTS 以上版本，再參考以下步驟啟動與打包：

```bash
cd web
npm install
npm run dev     # 啟動開發伺服器
npm run build   # 建置生產版本
```

目前錄影模組提供下列功能：

- 切換可用鏡頭並預覽畫面
- 選擇下載格式（WebM 或 MP4）
 - 自動多次錄影，可設定錄影次數、每段持續秒數與間隔秒數，並一次下載所有影片
- 錄影過程即時顯示目前錄製輪次與完成狀態
