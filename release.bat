@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1

:: =============================================================================
::  ORVIA 推版腳本（自託管 orvia.api.atk.tw 版 / Windows）
::  流程：build APK + AAB → PUT 版本設定 → POST 上傳 APK 至後端 /apks/
::  用法：
::    release.bat                            ← 互動式（選用更新）
::    release.bat -n "修正 bug" -n "新功能"  ← 帶更新說明
::    release.bat --force -n "重要更新"      ← 強制更新
::    release.bat --min 0.4.0               ← 指定最低支援版本
::    release.bat --no-aab                  ← 不打 AAB（只 APK）
::    release.bat --dry-run                 ← 模擬，不實際 build / 上傳
::
::  相依工具：Flutter SDK、curl（Windows 10+ 內建）、git
:: =============================================================================

:: ── ① 設定區（只需改這裡）─────────────────────────────────────────────────
set "ADMIN_KEY=xd6PbwIao9stGGjMu6qyHNB8N01qNxy5aULcChqrRZRNMEvFdZ"
set "API_BASE=https://orvia.api.atk.tw"
set "DOWNLOAD_BASE=%API_BASE%/apks"
:: Windows curl 需 --ssl-no-revoke 過憑證撤銷檢查
set "CURL=curl -s --ssl-no-revoke"

:: ── ② 解析參數 ────────────────────────────────────────────────────────────────
set "FORCE_UPDATE=false"
set "DRY_RUN=false"
set "BUILD_AAB=true"
set "MIN_VERSION="
set /a NOTE_COUNT=0

:parse_args
if "%~1"=="" goto :done_args
if /i "%~1"=="-f"        ( set "FORCE_UPDATE=true" & shift & goto :parse_args )
if /i "%~1"=="--force"   ( set "FORCE_UPDATE=true" & shift & goto :parse_args )
if /i "%~1"=="--dry-run" ( set "DRY_RUN=true"      & shift & goto :parse_args )
if /i "%~1"=="--no-aab"  ( set "BUILD_AAB=false"   & shift & goto :parse_args )
if /i "%~1"=="-m"        ( set "MIN_VERSION=%~2"   & shift & shift & goto :parse_args )
if /i "%~1"=="--min"     ( set "MIN_VERSION=%~2"   & shift & shift & goto :parse_args )
if /i "%~1"=="-n"        goto :add_note
if /i "%~1"=="--note"    goto :add_note
if /i "%~1"=="-h"        goto :usage
if /i "%~1"=="--help"    goto :usage
echo [ERROR] 未知參數: %~1
goto :usage

:add_note
set /a NOTE_COUNT+=1
set "NOTE_%NOTE_COUNT%=%~2"
shift & shift
goto :parse_args
:done_args

:: ── 路徑設定 ─────────────────────────────────────────────────────────────────
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "PUBSPEC=%SCRIPT_DIR%\pubspec.yaml"
set "APK_PATH=%SCRIPT_DIR%\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
set "AAB_PATH=%SCRIPT_DIR%\build\app\outputs\bundle\release\app-release.aab"

call :main
goto :eof

:: =============================================================================
:usage
echo.
echo ORVIA 推版腳本（自託管 / Windows）
echo.
echo 用法: %~nx0 [選項]
echo.
echo 選項:
echo   -n, --note ^<文字^>    新增更新說明（可重複）
echo   -f, --force          強制更新（min 預設=本次版本）
echo   -m, --min ^<版本^>     最低支援版本（覆寫預設）
echo       --no-aab         不打 AAB（只 APK）
echo       --dry-run        模擬執行，不實際 build 或上傳
echo   -h, --help           顯示說明
echo.
exit /b 0

:: =============================================================================
:read_pubspec_version
for /f "delims=" %%a in ('powershell -NoProfile -Command "(Select-String -Path '%PUBSPEC%' -Pattern '^version:').Line -replace '^version:\s*','' | ForEach-Object { $_.Trim() }"') do set "FULL_VERSION=%%a"
if "!FULL_VERSION!"=="" ( echo [ERROR] 無法讀取 pubspec.yaml 版本號 & exit /b 1 )
for /f "tokens=1 delims=+" %%a in ("!FULL_VERSION!") do set "V_NAME=%%a"
exit /b 0

:: =============================================================================
:check_env
echo.
echo ══════════════════════════════════════════
echo   環境檢查
echo ══════════════════════════════════════════
where flutter >nul 2>&1 || ( echo [ERROR] flutter 未安裝，請先安裝 Flutter SDK & exit /b 1 )
where curl    >nul 2>&1 || ( echo [ERROR] curl 未安裝（Windows 10+ 應已內建） & exit /b 1 )
where git     >nul 2>&1 || ( echo [ERROR] git 未安裝 & exit /b 1 )
echo   [OK] 工具檢查通過
exit /b 0

:: =============================================================================
:prompt_notes
if !NOTE_COUNT! GTR 0 exit /b 0
echo.
echo   請輸入更新說明（每行一條，直接按 Enter 結束）：
:_note_loop
set "INPUT_LINE="
set /p "INPUT_LINE=  -^> "
if "!INPUT_LINE!"=="" goto :_note_end
set /a NOTE_COUNT+=1
set "NOTE_%NOTE_COUNT%=!INPUT_LINE!"
goto :_note_loop
:_note_end
if !NOTE_COUNT! EQU 0 ( echo [ERROR] 至少需要一條更新說明 & exit /b 1 )
exit /b 0

:: =============================================================================
:confirm_release
set "_FORCE_DISP=否"
if "!FORCE_UPDATE!"=="true" set "_FORCE_DISP=是"
set "_AAB_DISP=否"
if "!BUILD_AAB!"=="true" set "_AAB_DISP=是"
echo.
echo   ┌─────────────────────────────────────────────
echo   │  版本         v!V_NAME!  （pubspec: !FULL_VERSION!）
echo   │  最低支援版本  !MIN_VERSION!
echo   │  強制更新      !_FORCE_DISP!
echo   │  打包 AAB      !_AAB_DISP!
echo   │  上傳端點      %API_BASE%/api/admin/app/version/android/apk
echo   │  更新說明
for /l %%i in (1,1,!NOTE_COUNT!) do echo   │    . !NOTE_%%i!
if "!DRY_RUN!"=="true" echo   │  [DRY RUN] 不會實際 build / 上傳
echo   └─────────────────────────────────────────────
echo.
set "CONFIRM="
set /p "CONFIRM=  確認推版？(y/N) "
if /i not "!CONFIRM!"=="y" ( echo   已取消 & exit /b 1 )
exit /b 0

:: =============================================================================
:build_apk
echo.
echo ══════════════════════════════════════════
echo   Build Release APK
echo ══════════════════════════════════════════
if "!DRY_RUN!"=="true" ( echo   [DRY RUN] 跳過 flutter build apk & exit /b 0 )
echo   flutter build apk --release --split-per-abi
call flutter build apk --release --split-per-abi
if errorlevel 1 ( echo [ERROR] flutter build apk 失敗 & exit /b 1 )
if not exist "!APK_PATH!" ( echo [ERROR] 找不到 APK：!APK_PATH! & exit /b 1 )
echo   [OK] APK 完成：!APK_PATH!
exit /b 0

:: =============================================================================
:build_aab
if "!BUILD_AAB!"=="false" exit /b 0
echo.
echo ══════════════════════════════════════════
echo   Build Release AAB
echo ══════════════════════════════════════════
if "!DRY_RUN!"=="true" ( echo   [DRY RUN] 跳過 flutter build appbundle & exit /b 0 )
echo   flutter build appbundle --release
call flutter build appbundle --release
if errorlevel 1 ( echo [ERROR] flutter build appbundle 失敗 & exit /b 1 )
if not exist "!AAB_PATH!" ( echo [ERROR] 找不到 AAB：!AAB_PATH! & exit /b 1 )
echo   [OK] AAB 完成：!AAB_PATH!
exit /b 0

:: =============================================================================
:update_backend
echo.
echo ══════════════════════════════════════════
echo   更新後端版本設定（PUT）
echo ══════════════════════════════════════════

if exist "%TEMP%\release_notes.txt" del "%TEMP%\release_notes.txt"
for /l %%i in (1,1,!NOTE_COUNT!) do echo !NOTE_%%i!>>"%TEMP%\release_notes.txt"

set "PS_V=!V_NAME!"
set "PS_MIN=!MIN_VERSION!"
set "PS_FORCE=!FORCE_UPDATE!"
set "PS_URL=%DOWNLOAD_BASE%/android-!V_NAME!.apk"
powershell -NoProfile -Command "$f=\"$env:TEMP\release_notes.txt\"; $notes=[string[]]@(Get-Content -Encoding UTF8 $f); $na=($notes | ForEach-Object { $_ | ConvertTo-Json }) -join ','; $force='false'; if($env:PS_FORCE -eq 'true'){$force='true'}; $json='{\"latestVersion\":\"'+$env:PS_V+'\",\"minRequiredVersion\":\"'+$env:PS_MIN+'\",\"forceUpdate\":'+$force+',\"updateUrl\":\"'+$env:PS_URL+'\",\"releaseNotes\":['+$na+'],\"releaseDate\":\"'+(Get-Date -Format 'yyyy-MM-dd')+'\"}'; [IO.File]::WriteAllText(\"$env:TEMP\release_payload.json\",$json,(New-Object Text.UTF8Encoding $false))"
if errorlevel 1 ( echo [ERROR] 無法建立 JSON payload & exit /b 1 )

if "!DRY_RUN!"=="true" (
  echo   [DRY RUN] 跳過 PUT
  type "%TEMP%\release_payload.json"
  exit /b 0
)

echo   PUT %API_BASE%/api/admin/app/version/android
for /f "delims=" %%c in ('%CURL% -o "%TEMP%\release_resp.json" -w "%%{http_code}" -X PUT "%API_BASE%/api/admin/app/version/android" -H "Content-Type: application/json" -H "X-Admin-Key: %ADMIN_KEY%" --data-binary "@%TEMP%\release_payload.json" --max-time 30') do set "HTTP_CODE=%%c"
if "!HTTP_CODE!"=="200" (
  echo   [OK] 後端版本設定已更新
  powershell -NoProfile -Command "$r=Get-Content \"$env:TEMP\release_resp.json\"|ConvertFrom-Json; Write-Host \"  版本：$($r.data.latestVersion)  最低：$($r.data.minRequiredVersion)  強制：$($r.data.forceUpdate)\""
) else (
  echo [ERROR] PUT 回應 !HTTP_CODE!
  type "%TEMP%\release_resp.json"
  exit /b 1
)
exit /b 0

:: =============================================================================
:upload_apk
echo.
echo ══════════════════════════════════════════
echo   上傳 APK 至自託管（POST）
echo ══════════════════════════════════════════
if "!DRY_RUN!"=="true" ( echo   [DRY RUN] 跳過上傳 & exit /b 0 )
echo   POST %API_BASE%/api/admin/app/version/android/apk
for /f "delims=" %%c in ('%CURL% -o "%TEMP%\apk_resp.json" -w "%%{http_code}" -X POST "%API_BASE%/api/admin/app/version/android/apk" -H "X-Admin-Key: %ADMIN_KEY%" -F "file=@!APK_PATH!;type=application/vnd.android.package-archive" --max-time 300') do set "HTTP_CODE=%%c"
if "!HTTP_CODE!"=="200" (
  echo   [OK] APK 上傳完成
  powershell -NoProfile -Command "$r=Get-Content \"$env:TEMP\apk_resp.json\"|ConvertFrom-Json; Write-Host \"  檔名：$($r.fileName)  下載：$($r.downloadUrl)  大小：$($r.sizeKb)KB\""
) else (
  echo [ERROR] POST 回應 !HTTP_CODE!
  type "%TEMP%\apk_resp.json"
  exit /b 1
)
exit /b 0

:: =============================================================================
:git_tag
echo.
echo ══════════════════════════════════════════
echo   Git Tag
echo ══════════════════════════════════════════
set "TAG=v!V_NAME!"
if "!DRY_RUN!"=="true" ( echo   [DRY RUN] 跳過 git tag !TAG! & exit /b 0 )
git rev-parse "!TAG!" >nul 2>&1
if not errorlevel 1 ( echo   [WARN] Tag !TAG! 已存在，略過 & exit /b 0 )
(
  echo Release !TAG!
  echo.
  for /l %%i in (1,1,!NOTE_COUNT!) do echo - !NOTE_%%i!
) > "%TEMP%\tag_message.txt"
git tag -a "!TAG!" -F "%TEMP%\tag_message.txt"
if errorlevel 1 ( echo [ERROR] git tag 失敗 & exit /b 1 )
git push origin "!TAG!"
if errorlevel 1 ( echo [WARN] git push tag 失敗，請手動執行 & exit /b 0 )
echo   [OK] 已建立並推送 tag !TAG!
exit /b 0

:: =============================================================================
:print_summary
echo.
echo ══════════════════════════════════════════
echo   推版完成！
echo ══════════════════════════════════════════
echo   版本：    v!V_NAME!
echo   APK URL： %DOWNLOAD_BASE%/android-!V_NAME!.apk
echo   latest：  %DOWNLOAD_BASE%/android-latest.apk
if "!BUILD_AAB!"=="true" echo   AAB：     !AAB_PATH!（供 Play Console 手動上傳）
set "_FDISP=否"
if "!FORCE_UPDATE!"=="true" set "_FDISP=是"
echo   強制更新：!_FDISP!
echo.
echo   [OK] 用戶下次開啟 App 將收到更新提示。
echo.
exit /b 0

:: =============================================================================
:main
echo.
echo ══════════════════════════════════════════
echo   ORVIA 推版腳本（自託管 orvia.api.atk.tw）
echo ══════════════════════════════════════════

call :read_pubspec_version
if errorlevel 1 exit /b 1

:: 預設 min：強制→本次版本；非強制→0.0.0；--min 覆寫
if "!MIN_VERSION!"=="" (
  if "!FORCE_UPDATE!"=="true" ( set "MIN_VERSION=!V_NAME!" ) else ( set "MIN_VERSION=0.0.0" )
)

call :prompt_notes
if errorlevel 1 exit /b 1
call :confirm_release
if errorlevel 1 exit /b 0
call :check_env
if errorlevel 1 exit /b 1
call :build_apk
if errorlevel 1 exit /b 1
call :build_aab
if errorlevel 1 exit /b 1
call :update_backend
if errorlevel 1 exit /b 1
call :upload_apk
if errorlevel 1 exit /b 1
call :git_tag
call :print_summary
exit /b 0
