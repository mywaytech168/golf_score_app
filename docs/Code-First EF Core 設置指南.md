# 🚀 Code-First EF Core 設置完成

**完成時間**：2026-01-27  
**進度**：✅ 已完成 EF Core 整合

---

## 📦 已實施的改動

### 1️⃣ **VideoDbContext.cs** - EF Core DbContext
- ✅ 建立完整的 DbContext 類
- ✅ 配置所有實體的映射（5 個表）
- ✅ 設定外鍵和導航屬性
- ✅ 建立索引以優化查詢
- ✅ 支持 MySQL 自動時間戳 (CURRENT_TIMESTAMP, ON UPDATE)

**位置**：`server/Data/VideoDbContext.cs`

### 2️⃣ **Program.cs** - 依賴注入配置
- ✅ 新增 `AddDbContext<VideoDbContext>()` 註冊
- ✅ 配置 MySQL 連接字符串
- ✅ 自動建立資料庫 (`EnsureCreated()`)
- ✅ 注冊 VideoUploadService
- ✅ 新增控制器和 Swagger

**關鍵程式碼**：
```csharp
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection");
builder.Services.AddDbContext<VideoDbContext>(options =>
{
    options.UseMySql(connectionString, ServerVersion.AutoDetect(connectionString));
});
```

### 3️⃣ **appsettings.json** - 連接字符串
- ✅ 新增 MySQL 連接字符串
- ✅ 設定字符編碼為 UTF-8

**內容**：
```json
"ConnectionStrings": {
  "DefaultConnection": "Server=localhost;Database=VideoSliceUploadDB;Uid=root;Pwd=;..."
}
```

### 4️⃣ **VideoController.cs** - 實現真實資料庫操作
- ✅ 新增 DbContext 注入
- ✅ CreateVideo() - 直接插入資料庫
- ✅ GetVideos() - 帶分頁和篩選的查詢
- ✅ GetVideoStatus() - 獲取影片及所有切片
- ✅ RetrySlice() - 重試失敗的切片
- ✅ HealthCheck() - 健康檢查端點

**API 端點總覽**：

| 端點 | 方法 | 功能 | 狀態 |
|------|------|------|------|
| `/api/videos/create` | POST | 建立影片 | ✅ 實現 |
| `/api/slices/upload` | POST | 上傳切片 | ✅ 實現 |
| `/api/videos` | GET | 列表查詢 | ✅ 實現 |
| `/api/videos/{id}/status` | GET | 狀態查詢 | ✅ 實現 |
| `/api/slices/{id}/retry` | POST | 重試切片 | ✅ 實現 |
| `/api/slices/{id}/download/{fileName}` | GET | 下載結果 | ⚠️ 骨架 |
| `/api/health` | GET | 健康檢查 | ✅ 實現 |

---

## 🔧 必要的 NuGet 包安裝

### 執行以下命令安裝 EF Core 相關包

```bash
# 進入 server 目錄
cd server

# 安裝 EF Core MySql Provider
dotnet add package Pomelo.EntityFrameworkCore.MySql --version 7.0.*

# 安裝 EF Core 核心包
dotnet add package Microsoft.EntityFrameworkCore --version 7.0.*

# 安裝 EF Core 工具（用於遷移）
dotnet add package Microsoft.EntityFrameworkCore.Tools --version 7.0.*

# 恢復所有依賴
dotnet restore
```

### 預期安裝的包：
```
✅ Pomelo.EntityFrameworkCore.MySql (EF Core MySql 驅動)
✅ Microsoft.EntityFrameworkCore (核心)
✅ Microsoft.EntityFrameworkCore.Abstractions
✅ Microsoft.EntityFrameworkCore.Analyzers
✅ Microsoft.EntityFrameworkCore.Tools
```

---

## 📊 資料庫初始化方式

### 方法 1：自動初始化（推薦）
```csharp
// Program.cs 中已配置
using (var scope = app.Services.CreateScope())
{
    var dbContext = scope.ServiceProvider.GetRequiredService<VideoDbContext>();
    dbContext.Database.EnsureCreated();  // 自動建立表和關係
    Console.WriteLine("✅ 資料庫已初始化");
}
```

**優點**：
- 無需手動執行 SQL
- 自動建立所有表、索引、外鍵
- 支持應用程式自動遷移

### 方法 2：手動執行 SQL（可選）
如果希望使用預先定義的 SQL 腳本：
```bash
mysql -u root -p VideoSliceUploadDB < server/database-init.sql
```

**注意**：不要同時使用兩種方法，選擇其中一種

---

## ✅ 驗證設置

### 1. 編譯檢查
```bash
cd server
dotnet build
```

**預期結果**：✅ Build succeeded

### 2. 執行應用
```bash
dotnet run
```

**預期日誌輸出**：
```
✅ 資料庫已初始化（Code-First）
🚀 伺服器啟動中...
📍 連接字符串: Server=localhost;Database=VideoSliceUploadDB;Uid=root;Pwd=;...
📁 上傳目錄: C:\...\Uploads
```

### 3. 測試 API
```bash
# 建立影片
curl -X POST http://localhost:5000/api/videos/create \
  -H "Content-Type: application/json" \
  -d '{"name":"test_video","user_id":1,"total_slices":3}'

# 預期響應
{
  "success": true,
  "video_id": 1,
  "name": "test_video",
  "status": "pending",
  "total_slices": 3,
  "created_at": "2026-01-27T..."
}
```

### 4. 驗證資料庫
```bash
# 連接 MySQL
mysql -u root -p VideoSliceUploadDB

# 檢查表
SHOW TABLES;

# 檢查 videos 表結構
DESCRIBE videos;

# 查詢資料
SELECT * FROM videos;
```

---

## 🔍 數據流圖

```
前端上傳 (Flutter)
    ↓
HTTP POST /api/slices/upload
    ↓
VideoController.UploadSlice()
    ↓
├─ 驗證 video_id 存在
├─ VideoUploadService.UploadSliceAsync()
│  └─ 儲存檔案到磁盤
├─ 建立 Slice 實體
├─ _context.Slices.Add(slice)
├─ _context.SaveChangesAsync()
    ↓
✅ 200 OK + SliceId
    ↓
前端更新本地 SQLite
    ↓
定期輪詢 GET /api/videos/{id}/status
    ↓
VideoController.GetVideoStatus()
    ↓
從資料庫查詢 Slice 最新狀態
    ↓
返回 { Slices: [...], Status: "..." }
```

---

## 🛠️ 調試技巧

### 啟用 EF Core SQL 日誌
```csharp
// Program.cs 中添加
using (var scope = app.Services.CreateScope())
{
    var dbContext = scope.ServiceProvider.GetRequiredService<VideoDbContext>();
    
    // 啟用 SQL 日誌
    dbContext.Database.LogSqlStatements = true;
    
    dbContext.Database.EnsureCreated();
}
```

### 檢查 DbContext 生成的 SQL
```csharp
// 使用 EF Core Power Tools（VS 擴展）
// 或檢查程序日誌中的 SQL 陳述句
```

### MySQL 連接問題排查
```bash
# 驗證 MySQL 服務運行
mysql -u root -p -e "SELECT 1;"

# 檢查連接字符串
# appsettings.json 中的 Server=localhost;Database=VideoSliceUploadDB

# 確認資料庫存在
mysql -u root -p -e "SHOW DATABASES;"

# 如果不存在，可先建立
mysql -u root -p -e "CREATE DATABASE VideoSliceUploadDB CHARACTER SET utf8mb4;"
```

---

## 📋 下一步

### ✅ 已完成
1. EF Core DbContext 設置
2. 控制器實現資料庫操作
3. 自動資料庫初始化

### ⏳ 待完成
1. **前端上傳邏輯** - 實現 VideoServerClient 中的實際檔案讀取
2. **測試集成** - 端到端測試前端↔後端通信
3. **背景服務** - 實現切片處理隊列
4. **Python 調用** - 連接 Python 影片處理

---

**🎉 Code-First 實施完成！伺服器已準備好進行整合測試**
