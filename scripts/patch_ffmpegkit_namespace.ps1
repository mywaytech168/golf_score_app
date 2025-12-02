Param()

# Patch FFmpegKit plugin build.gradle in pub cache to add 'namespace' for AGP compatibility.
# Usage (Windows cmd):
#   powershell -ExecutionPolicy Bypass -File scripts\patch_ffmpegkit_namespace.ps1

Write-Host "Searching for ffmpeg_kit_flutter_min_gpl plugin in local pub cache..."

$userProfile = $Env:USERPROFILE
$pubCachePaths = @(
  "$userProfile\.pub-cache\hosted\pub.dev",
  "$userProfile\AppData\Local\Pub\Cache\hosted\pub.dev",
)

$found = $false
foreach ($base in $pubCachePaths) {
  $candidate = Join-Path $base "ffmpeg_kit_flutter_min_gpl-5.1.0\android\build.gradle"
  if (Test-Path $candidate) {
    Write-Host "Found: $candidate"
    $content = Get-Content $candidate -Raw
    if ($content -match "\bnamespace\b") {
      Write-Host "Namespace already present in build.gradle; no changes made." -ForegroundColor Yellow
    } else {
      # Insert namespace declaration inside the first 'android {' block
      $newContent = $content -replace '(android\s*\{)', "`$1`r`n    namespace = 'com.arthenica.ffmpeg_kit_flutter_min_gpl'"
      if ($newContent -ne $content) {
        # Backup original
        Copy-Item $candidate "$candidate.bak" -Force
        $newContent | Set-Content $candidate -Encoding UTF8
        Write-Host "Patched build.gradle and created backup: $candidate.bak" -ForegroundColor Green
      } else {
        Write-Host "Could not apply patch automatically - please edit the file and add a namespace property inside the android { } block." -ForegroundColor Red
      }
    }
    $found = $true
    break
  }
}

if (-not $found) {
  Write-Host "Could not find ffmpeg_kit_flutter_min_gpl plugin in pub cache. Please run 'flutter pub get' first or adjust the script to your pub cache location." -ForegroundColor Red
}

Write-Host "Done. If a patch was applied, run: flutter clean && flutter pub get && flutter run -d <device>" -ForegroundColor Cyan
