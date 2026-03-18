# C# Server 部署指南 - 7 大安全性及性能修復

## 📋 目錄
1. [環境變數設置](#環境變數設置)
2. [NuGet 套件安裝](#nuget-套件安裝)
3. [配置文件設置](#配置文件設置)
4. [資料庫連接測試](#資料庫連接測試)
5. [速率限制監控](#速率限制監控)
6. [檔案大小驗證](#檔案大小驗證)
7. [安全性檢查清單](#安全性檢查清單)
8. [故障排查](#故障排查)
9. [回滾計畫](#回滾計畫)

---

## 環境變數設置

### 1️⃣ JWT 密鑰配置 (修復 6️⃣)

**⚠️ 關鍵**: JWT 密鑰不應硬編碼在代碼中

```bash
# Windows PowerShell
[Environment]::SetEnvironmentVariable("JWT_SECRET", "your-very-long-and-secure-key-at-least-32-chars", "User")

# Linux/macOS
export JWT_SECRET="your-very-long-and-secure-key-at-least-32-chars"

# Docker
ENV JWT_SECRET="your-very-long-and-secure-key-at-least-32-chars"
```

**密鑰安全要求**:
- ✅ 最少 32 個字符
- ✅ 包含大寫字母、小寫字母、數字、特殊字符
- ✅ 使用密鑰生成工具生成

**密鑰生成命令**:
```powershell
# PowerShell - 生成 64 字符的隨機密鑰
$key = [System.Convert]::ToBase64String((1..64 | ForEach-Object { [byte](Get-Random -Minimum 0 -Maximum 256) }))
Write-Host "JWT_SECRET=$key"
```

### 2️⃣ 檔案上傳目錄 (修復 1️⃣)

```bash
# 設置檔案上傳目錄
FILE_UPLOAD_DIR="/var/uploads"  # Linux
FILE_UPLOAD_DIR="D:\Uploads"    # Windows

# 設置最大檔案大小 (500 MB 預設)
MAX_FILE_SIZE_MB=500
```

### 3️⃣ 資料庫連接 (修復 5️⃣)

```bash
# MySQL 連接字符串 (包含連接池設置)
DATABASE_URL="Server=db.example.com;User Id=admin;Password=secure_pwd;Database=golf_app;Pooling=true;Min Pool Size=5;Max Pool Size=50"

# 或個別設置
DB_HOST=db.example.com
DB_USER=admin
DB_PASSWORD=secure_pwd
DB_NAME=golf_app
DB_PORT=3306
```

### 4️⃣ 日誌級別 (修復 3️⃣)

```bash
# 開發環境 - 詳細日誌
LOG_LEVEL=Debug

# 生產環境 - 精簡日誌
LOG_LEVEL=Information
```

---

## NuGet 套件安裝

### 必需的套件

```bash
# 執行以下命令安裝必需的 NuGet 套件
dotnet add package Microsoft.EntityFrameworkCore.MySql --version 7.0.0
dotnet add package MySqlConnector --version 2.2.0
dotnet add package System.IdentityModel.Tokens.Jwt --version 7.0.0
dotnet add package Microsoft.IdentityModel.Protocols.OpenIdConnect --version 7.0.0
dotnet add package AspNetCoreRateLimit --version 4.0.1
dotnet add package NLog --version 5.2.0
dotnet add package NLog.Extensions.Logging --version 5.3.0
```

### 驗證安裝

```bash
# 檢查已安裝的套件
dotnet list package
```

**預期輸出**:
```
Project 'UploadServer' has the following package references
   NuGet package                                   Requested   Resolved
   Microsoft.EntityFrameworkCore.MySql             7.0.0       7.0.0
   AspNetCoreRateLimit                             4.0.1       4.0.1
   NLog.Extensions.Logging                         5.3.0       5.3.0
```

---

## 配置文件設置

### appsettings.Development.json

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Debug",
      "Microsoft": "Information",
      "UploadServer": "Debug"
    }
  },
  "ConnectionStrings": {
    "DefaultConnection": "Server=localhost;User Id=root;Password=dev_password;Database=golf_app_dev;Pooling=true;Min Pool Size=5;Max Pool Size=20"
  },
  "FileUpload": {
    "MaxFileSizeMB": 500,
    "UploadDirectory": "./uploads",
    "AllowedExtensions": [
      "mp4", "mov", "avi", "mkv",      // 視頻
      "wav", "mp3", "aac", "flac",    // 音頻
      "jpg", "jpeg", "png", "gif",    // 圖像
      "csv", "json", "xml"            // 數據
    ]
  },
  "Jwt": {
    "Issuer": "GolfApp",
    "Audience": "GolfAppUsers",
    "ExpirationMinutes": 60
  },
  "RateLimiting": {
    "IpWhitelist": [],
    "GeneralRule": {
      "Limit": 100,
      "Period": "1m"
    },
    "UserRule": {
      "Limit": 1000,
      "Period": "1h"
    }
  }
}
```

### appsettings.Production.json

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Warning",
      "Microsoft": "Warning",
      "UploadServer": "Information"
    }
  },
  "ConnectionStrings": {
    "DefaultConnection": "Server=${DB_HOST};User Id=${DB_USER};Password=${DB_PASSWORD};Database=${DB_NAME};Pooling=true;Min Pool Size=10;Max Pool Size=50;Connection Idle Timeout=300"
  },
  "FileUpload": {
    "MaxFileSizeMB": 500,
    "UploadDirectory": "/var/uploads",
    "AllowedExtensions": [
      "mp4", "mov", "avi",
      "wav", "mp3",
      "jpg", "jpeg", "png",
      "csv", "json"
    ]
  },
  "Jwt": {
    "Issuer": "GolfApp",
    "Audience": "GolfAppUsers",
    "ExpirationMinutes": 30,
    "KeyRotationDays": 90
  },
  "RateLimiting": {
    "IpWhitelist": ["10.0.0.0/8"],
    "GeneralRule": {
      "Limit": 100,
      "Period": "1m"
    },
    "UserRule": {
      "Limit": 1000,
      "Period": "1h"
    }
  }
}
```

### .env 文件範本

```bash
# .env.template (複製為 .env 並填入實際值)

# === JWT 配置 ===
JWT_SECRET=your-very-long-and-secure-key-at-least-32-chars-here

# === 資料庫配置 ===
DB_HOST=localhost
DB_PORT=3306
DB_USER=admin
DB_PASSWORD=secure_password_here
DB_NAME=golf_app

# === 檔案上傳配置 ===
FILE_UPLOAD_DIR=/var/uploads
MAX_FILE_SIZE_MB=500

# === 日誌配置 ===
LOG_LEVEL=Information

# === 環境 ===
ASPNETCORE_ENVIRONMENT=Production
```

---

## 資料庫連接測試

### 1. 測試基本連接

```bash
# 使用 MySQL 客戶端測試
mysql -h localhost -u admin -p

# 執行以下 SQL 驗證連接和權限
SELECT VERSION();
USE golf_app;
SHOW TABLES;
```

### 2. 驗證連接池設置

```csharp
// Program_Improved.cs 中驗證連接池

var connectionString = builder.Configuration.GetConnectionString("DefaultConnection");
Console.WriteLine($"連接字符串: {connectionString}");
Console.WriteLine("預期包含: Pooling=true, Min Pool Size=5, Max Pool Size=50");
```

### 3. 測試應用連接

```bash
# 編譯應用
dotnet build

# 運行遷移
dotnet ef database update

# 測試連接
dotnet run

# 查看日誌輸出
# [11:23:45 INF] 資料庫連接已建立
# [11:23:45 INF] 連接池: Min=5, Max=50
```

---

## 速率限制監控

### 1. 檢查速率限制配置

```bash
# 查看 Program_Improved.cs 中的配置
grep -n "RateLimit" Program_Improved.cs

# 預期輸出:
# - IP 級別: 100 requests/分鐘
# - 用戶級別: 1000 requests/小時
```

### 2. 監控速率限制觸發

```bash
# 查看日誌中的限流警告
grep -i "rate limit\|429" logs/application.log

# 預期日誌條目:
# [WARN] Rate limit exceeded for user user123 (1050 requests in 1 hour)
# [INFO] Request rejected: 429 Too Many Requests
```

### 3. 測試速率限制

```bash
# 使用 curl 快速進行多個請求
for i in {1..150}; do
  curl -H "Authorization: Bearer $TOKEN" \
       http://localhost:5000/api/videos \
       -w "Status: %{http_code}\n"
done

# 預期: 前 100 個請求返回 200，後續返回 429
```

---

## 檔案大小驗證

### 1. 驗證 500 MB 限制

```bash
# 建立測試檔案 (100 MB)
dd if=/dev/zero of=test_file.mp4 bs=1M count=100

# 嘗試上傳 (應成功)
curl -F "file=@test_file.mp4" \
     http://localhost:5000/api/videos/video123/files

# 預期: 200 OK

# 建立大型測試檔案 (600 MB)
dd if=/dev/zero of=large_file.mp4 bs=1M count=600

# 嘗試上傳 (應失敗)
curl -F "file=@large_file.mp4" \
     http://localhost:5000/api/videos/video123/files

# 預期: 413 Payload Too Large 或 400 Bad Request
```

### 2. 驗證檔案類型驗證

```bash
# 嘗試上傳可執行檔案
echo "#!/bin/bash" > malicious.sh

curl -F "file=@malicious.sh" \
     -F "fileType=video" \
     http://localhost:5000/api/videos/video123/files

# 預期: 400 Bad Request with error message
# "檔案類型 .sh 不允許"
```

---

## 安全性檢查清單

### 部署前檢查

- [ ] **JWT 密鑰**
  - [ ] 從環境變數 `JWT_SECRET` 讀取
  - [ ] 密鑰長度 ≥ 32 個字符
  - [ ] 不在代碼中硬編碼

- [ ] **檔案上傳安全**
  - [ ] 最大大小限制為 500 MB
  - [ ] 檔案類型白名單已配置
  - [ ] 檔案簽名驗證已啟用

- [ ] **資料庫安全**
  - [ ] 連接池已啟用 (Min=5, Max=50)
  - [ ] 密碼未在代碼中硬編碼
  - [ ] 使用環境變數存儲敏感信息

- [ ] **速率限制**
  - [ ] IP 級別限制已配置 (100 req/min)
  - [ ] 用戶級別限制已配置 (1000 req/hour)
  - [ ] 日誌記錄已啟用

- [ ] **日誌記錄**
  - [ ] 生產環境日誌級別設為 Warning/Information
  - [ ] 敏感信息未記錄
  - [ ] 日誌輪轉已配置

- [ ] **HTTPS 配置**
  - [ ] SSL/TLS 證書已安裝
  - [ ] HTTP 重定向到 HTTPS
  - [ ] HSTS 頭已設置

- [ ] **CORS 配置**
  - [ ] 只允許受信任的域

---

## 故障排查

### 問題 1: JWT 密鑰未找到

**症狀**:
```
InvalidOperationException: JWT_SECRET environment variable not found
```

**解決方案**:
```bash
# 1. 設置環境變數
export JWT_SECRET="your-secure-key"

# 2. 驗證設置
echo $JWT_SECRET

# 3. 重新啟動應用
dotnet run
```

### 問題 2: 資料庫連接失敗

**症狀**:
```
MySqlConnector.MySqlException: Access denied for user 'admin'@'localhost'
```

**解決方案**:
```bash
# 1. 驗證 MySQL 服務運行
systemctl status mysql  # Linux
Get-Service MySQL80     # Windows

# 2. 測試連接
mysql -h localhost -u admin -p

# 3. 驗證連接字符串
grep "DefaultConnection" appsettings.json

# 4. 檢查連接池配置
# 確保包含: Pooling=true;Min Pool Size=5;Max Pool Size=50
```

### 問題 3: 檔案上傳失敗

**症狀**:
```
DirectoryNotFoundException: Could not find a part of the path '/var/uploads'
```

**解決方案**:
```bash
# 1. 建立上傳目錄
mkdir -p /var/uploads
chmod 755 /var/uploads

# 2. 設置環境變數
export FILE_UPLOAD_DIR="/var/uploads"

# 3. 驗證權限
ls -la /var/uploads
```

### 問題 4: 速率限制不生效

**症狀**:
```
超過限制的請求仍然被接受
```

**解決方案**:
```bash
# 1. 驗證中間件註冊順序
grep -A5 "app.UseMiddleware" Program.cs

# 2. 檢查速率限制配置
grep -A10 "RateLimit" appsettings.json

# 3. 查看日誌級別
# 確保設為 Debug 或 Information 以查看限流日誌

# 4. 重新啟動應用
dotnet run
```

### 問題 5: N+1 查詢影響性能

**症狀**:
```
資料庫查詢次數過多 (例如: 1 + N)
```

**解決方案**:
```csharp
// 檢查 VideoController_Improvements.cs 中使用 .Include()

// ❌ 不好 (N+1 查詢)
var videos = await _context.Videos.ToListAsync();
foreach (var video in videos)
{
    var files = await _context.Files.Where(f => f.VideoId == video.Id).ToListAsync();
}

// ✅ 好 (1 個查詢)
var videos = await _context.Videos
    .Include(v => v.Files)
    .ToListAsync();
```

---

## 回滾計畫

如果新版本出現問題，可以快速回滾到舊版本:

### 1. 備份當前配置和數據

```bash
# 備份資料庫
mysqldump -u admin -p golf_app > backup_prod_2024.sql

# 備份應用配置
tar -czf backup_config_2024.tar.gz appsettings.*.json

# 備份上傳的檔案
tar -czf backup_uploads_2024.tar.gz /var/uploads
```

### 2. 快速回滾步驟

```bash
# 1. 停止應用
sudo systemctl stop UploadServer

# 2. 還原舊版本代碼
git checkout v1.0.0  # 或使用備份

# 3. 還原舊配置
cp appsettings.backup.json appsettings.Production.json

# 4. 還原資料庫 (如必要)
mysql -u admin -p golf_app < backup_prod_2024.sql

# 5. 重新啟動應用
sudo systemctl start UploadServer

# 6. 驗證服務狀態
curl http://localhost:5000/api/health
```

### 3. 驗證回滾

```bash
# 檢查應用日誌
tail -f /var/log/UploadServer/application.log

# 測試基本功能
curl -H "Authorization: Bearer $TOKEN" \
     http://localhost:5000/api/videos

# 檢查資料庫連接
# 應顯示: "Database connection pool: 5-50 connections"
```

### 4. 事後分析

```bash
# 收集問題信息
- 檢查應用日誌中的錯誤
- 檢查系統資源使用情況 (CPU, 記憶體, 磁盤)
- 分析性能指標 (查詢時間, 響應時間)
- 更新故障單，記錄根本原因
```

---

## 推薦的部署檢查

### 上線前 24 小時檢查

```bash
✅ JWT 密鑰已從環境變數讀取
✅ 資料庫連接池已配置和測試
✅ 檔案大小限制已驗證 (500 MB)
✅ 檔案類型驗證已測試
✅ 速率限制已測試
✅ 日誌級別已設置為 Production
✅ SSL/TLS 證書已安裝
✅ 備份已完成
✅ 回滾計畫已準備
✅ 監控告警已配置
```

### 上線後 24-48 小時檢查

```bash
✅ 所有日誌正常，無異常
✅ 性能指標符合預期
✅ 無資料庫連接池耗盡
✅ 速率限制運作正常
✅ 檔案上傳功能正常
✅ 用戶反饋無負面
✅ 系統資源使用正常
```

---

## 聯絡方式

部署問題或技術支援，請聯絡:
- 📧 技術團隊: tech-support@golfapp.com
- 📞 緊急熱線: +886-1-2345-6789
- 📋 文檔: https://wiki.golfapp.com/deploy

---

**最後更新**: 2024-01-15
**版本**: 1.0
**作者**: DevOps Team
