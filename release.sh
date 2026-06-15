#!/bin/bash
# =============================================================================
#  ORVIA 推版腳本（自託管 orvia.api.atk.tw 版）
#  流程：build APK + AAB → PUT 版本設定 → POST 上傳 APK 至後端 /apks/
#  用法：
#    ./release.sh                            ← 互動式（選用更新）
#    ./release.sh -n "修正 bug" -n "新功能"  ← 帶更新說明
#    ./release.sh --force -n "重要更新"      ← 強制更新
#    ./release.sh --min 0.4.0               ← 指定最低支援版本
#    ./release.sh --no-aab                  ← 不打 AAB（只 APK）
#    ./release.sh --dry-run                 ← 模擬，不實際 build / 上傳
# =============================================================================
set -euo pipefail

# ── ① 設定區（只需改這裡）────────────────────────────────────────────────────
ADMIN_KEY="xd6PbwIao9stGGjMu6qyHNB8N01qNxy5aULcChqrRZRNMEvFdZ"   # 後端 Admin:SecretKey
API_BASE="https://orvia.api.atk.tw"
# 自託管 APK 下載 URL（POST 上傳後由後端產生，格式固定如下）
DOWNLOAD_BASE="${API_BASE}/apks"

# ── 顏色 ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

print_header() {
  echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════${NC}"
  echo -e "${BOLD}${BLUE}  $1${NC}"
  echo -e "${BOLD}${BLUE}══════════════════════════════════════════${NC}"
}
print_ok()   { echo -e "  ${GREEN}✓${NC}  $1"; }
print_err()  { echo -e "  ${RED}✗${NC}  $1" >&2; exit 1; }
print_warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }
print_info() { echo -e "  ${CYAN}→${NC}  $1"; }

# ── ② 解析參數 ────────────────────────────────────────────────────────────────
FORCE_UPDATE=false
DRY_RUN=false
BUILD_AAB=true
MIN_VERSION=""
RELEASE_NOTES=()

usage() {
  echo ""
  echo -e "${BOLD}ORVIA 推版腳本（自託管）${NC}"
  echo ""
  echo "用法: $0 [選項]"
  echo ""
  echo "選項:"
  echo "  -n, --note <文字>    新增更新說明（可重複）"
  echo "  -f, --force          強制更新（min 預設=本次版本）"
  echo "  -m, --min <版本>     最低支援版本（覆寫預設）"
  echo "      --no-aab         不打 AAB（只 APK）"
  echo "      --dry-run        模擬執行，不實際 build 或上傳"
  echo "  -h, --help           顯示說明"
  echo ""
  exit 0
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -f|--force)   FORCE_UPDATE=true; shift ;;
    --dry-run)    DRY_RUN=true; shift ;;
    --no-aab)     BUILD_AAB=false; shift ;;
    -n|--note)    RELEASE_NOTES+=("$2"); shift 2 ;;
    -m|--min)     MIN_VERSION="$2"; shift 2 ;;
    -h|--help)    usage ;;
    *) echo -e "${RED}未知參數: $1${NC}"; usage ;;
  esac
done

# ── ③ 工具函式 ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBSPEC="$SCRIPT_DIR/pubspec.yaml"
CURL=(curl -s --ssl-no-revoke)   # Windows curl 需 --ssl-no-revoke 過憑證撤銷檢查

read_pubspec_version() {
  grep '^version:' "$PUBSPEC" | sed 's/version:[[:space:]]*//' | tr -d '[:space:]'
}
version_name() { echo "$1" | cut -d'+' -f1; }   # "1.1.0+2" → "1.1.0"
check_cmd() { command -v "$1" &>/dev/null || print_err "$1 未安裝。$2"; }

# ── ④ 環境檢查 ────────────────────────────────────────────────────────────────
check_env() {
  print_header "環境檢查"
  check_cmd flutter  "請先安裝 Flutter SDK"
  check_cmd curl     "請先安裝 curl"
  check_cmd jq       "請安裝 jq：brew install jq 或 sudo apt install jq"
  print_ok "flutter $(flutter --version 2>/dev/null | head -1 | awk '{print $2}')"
  print_ok "jq $(jq --version)"
}

# ── ⑤ 互動輸入更新說明 ───────────────────────────────────────────────────────
prompt_notes() {
  if [ ${#RELEASE_NOTES[@]} -eq 0 ]; then
    echo ""
    echo -e "  ${CYAN}請輸入更新說明（每行一條，直接按 Enter 結束）：${NC}"
    while IFS= read -r -p "  → " line; do
      [[ -z "$line" ]] && break
      RELEASE_NOTES+=("$line")
    done
    [ ${#RELEASE_NOTES[@]} -eq 0 ] && print_err "至少需要一條更新說明"
  fi
}

# ── ⑥ 確認摘要 ───────────────────────────────────────────────────────────────
confirm_release() {
  local v_full="$1" v_name="$2" min_ver="$3"
  echo ""
  echo -e "  ┌─────────────────────────────────────────────"
  echo -e "  │  ${BOLD}版本${NC}         v$v_name  （pubspec: $v_full）"
  echo -e "  │  ${BOLD}最低支援版本${NC}  $min_ver"
  echo -e "  │  ${BOLD}強制更新${NC}      $([ "$FORCE_UPDATE" = true ] && echo -e "${RED}是 🔴${NC}" || echo '否')"
  echo -e "  │  ${BOLD}打包 AAB${NC}      $([ "$BUILD_AAB" = true ] && echo '是' || echo '否')"
  echo -e "  │  ${BOLD}上傳端點${NC}      $API_BASE/api/admin/app/version/android/apk"
  echo -e "  │  ${BOLD}更新說明${NC}"
  for note in "${RELEASE_NOTES[@]}"; do echo -e "  │    • $note"; done
  [ "$DRY_RUN" = true ] && echo -e "  │  ${YELLOW}[DRY RUN] 不會實際 build / 上傳${NC}"
  echo -e "  └─────────────────────────────────────────────"
  echo ""
  read -r -p "  確認推版？(y/N) " confirm
  [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { print_warn "已取消"; exit 0; }
}

# ── ⑦ Flutter Build ──────────────────────────────────────────────────────────
APK_PATH="$SCRIPT_DIR/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
AAB_PATH="$SCRIPT_DIR/build/app/outputs/bundle/release/app-release.aab"

build_apk() {
  print_header "Build Release APK"
  if [ "$DRY_RUN" = true ]; then print_warn "[dry-run] 跳過 flutter build apk"; return; fi
  print_info "flutter build apk --release --split-per-abi"
  flutter build apk --release --split-per-abi 2>&1 | tail -6
  [ -f "$APK_PATH" ] || print_err "找不到 APK：$APK_PATH"
  print_ok "APK 完成（$(du -m "$APK_PATH" | cut -f1) MB）：$APK_PATH"
}

build_aab() {
  [ "$BUILD_AAB" = true ] || return
  print_header "Build Release AAB"
  if [ "$DRY_RUN" = true ]; then print_warn "[dry-run] 跳過 flutter build appbundle"; return; fi
  print_info "flutter build appbundle --release"
  flutter build appbundle --release 2>&1 | tail -5
  [ -f "$AAB_PATH" ] || print_err "找不到 AAB：$AAB_PATH"
  print_ok "AAB 完成（$(du -m "$AAB_PATH" | cut -f1) MB）：$AAB_PATH"
}

# ── ⑧ PUT 版本設定 ───────────────────────────────────────────────────────────
update_backend() {
  local v_name="$1" min_ver="$2"
  print_header "更新後端版本設定（PUT）"
  local today download_url notes_json payload
  today=$(date +%Y-%m-%d)
  download_url="${DOWNLOAD_BASE}/android-${v_name}.apk"
  notes_json=$(printf '%s\n' "${RELEASE_NOTES[@]}" | jq -R . | jq -s .)
  payload=$(jq -n \
    --arg latest "$v_name" --arg min "$min_ver" \
    --argjson force "$FORCE_UPDATE" --arg url "$download_url" \
    --argjson notes "$notes_json" --arg date "$today" \
    '{latestVersion:$latest,minRequiredVersion:$min,forceUpdate:$force,
      updateUrl:$url,releaseNotes:$notes,releaseDate:$date}')

  if [ "$DRY_RUN" = true ]; then print_warn "[dry-run] 跳過 PUT"; echo "  Payload: $payload"; return; fi

  print_info "PUT $API_BASE/api/admin/app/version/android"
  local resp http body
  resp=$("${CURL[@]}" -w "\n%{http_code}" -X PUT \
    "$API_BASE/api/admin/app/version/android" \
    -H "Content-Type: application/json" -H "X-Admin-Key: $ADMIN_KEY" \
    -d "$payload" --max-time 30)
  http=$(echo "$resp" | tail -1); body=$(echo "$resp" | head -n -1)
  [ "$http" = "200" ] || print_err "PUT 回應 $http\n  $body"
  print_ok "後端版本設定已更新"
  echo "$body" | jq -r '"  版本：\(.data.latestVersion)  最低：\(.data.minRequiredVersion)  強制：\(.data.forceUpdate)"' 2>/dev/null || true
}

# ── ⑨ POST 上傳 APK ──────────────────────────────────────────────────────────
upload_apk() {
  print_header "上傳 APK 至自託管（POST）"
  if [ "$DRY_RUN" = true ]; then print_warn "[dry-run] 跳過上傳"; return; fi
  print_info "POST $API_BASE/api/admin/app/version/android/apk"
  local resp http body
  resp=$("${CURL[@]}" -w "\n%{http_code}" -X POST \
    "$API_BASE/api/admin/app/version/android/apk" \
    -H "X-Admin-Key: $ADMIN_KEY" \
    -F "file=@${APK_PATH};type=application/vnd.android.package-archive" \
    --max-time 300)
  http=$(echo "$resp" | tail -1); body=$(echo "$resp" | head -n -1)
  [ "$http" = "200" ] || print_err "POST 回應 $http\n  $body"
  print_ok "APK 上傳完成"
  echo "$body" | jq -r '"  檔名：\(.fileName)  下載：\(.downloadUrl)  大小：\(.sizeKb)KB"' 2>/dev/null || true
}

# ── ⑩ Git Tag ────────────────────────────────────────────────────────────────
git_tag() {
  local v_name="$1"; local tag="v$v_name"
  print_header "Git Tag"
  if [ "$DRY_RUN" = true ]; then print_warn "[dry-run] 跳過 git tag $tag"; return; fi
  if git rev-parse "$tag" &>/dev/null 2>&1; then
    print_warn "Tag $tag 已存在，略過"
  else
    git tag -a "$tag" -m "Release $tag

$(printf '• %s\n' "${RELEASE_NOTES[@]}")"
    git push origin "$tag" 2>&1 | tail -2
    print_ok "已建立並推送 tag $tag"
  fi
}

# ── ⑪ 完成摘要 ───────────────────────────────────────────────────────────────
print_summary() {
  local v_name="$1"
  print_header "推版完成 🎉"
  echo -e "  版本：    ${BOLD}v$v_name${NC}"
  echo -e "  APK URL： ${CYAN}${DOWNLOAD_BASE}/android-${v_name}.apk${NC}"
  echo -e "  latest：  ${CYAN}${DOWNLOAD_BASE}/android-latest.apk${NC}"
  [ "$BUILD_AAB" = true ] && echo -e "  AAB：     ${CYAN}$AAB_PATH${NC}（供 Play Console 手動上傳）"
  echo -e "  強制更新：$([ "$FORCE_UPDATE" = true ] && echo -e "${RED}是${NC}" || echo '否')"
  echo ""
  print_ok "用戶下次開啟 App 將收到更新提示。"
}

# ── 主流程 ───────────────────────────────────────────────────────────────────
main() {
  print_header "ORVIA 推版腳本（自託管 orvia.api.atk.tw）"
  local full_version v_name min_version
  full_version=$(read_pubspec_version)
  v_name=$(version_name "$full_version")
  # 預設 min：強制更新→本次版本；非強制→0.0.0（不版本強制）；--min 可覆寫
  if [ -n "$MIN_VERSION" ]; then min_version="$MIN_VERSION"
  elif [ "$FORCE_UPDATE" = true ]; then min_version="$v_name"
  else min_version="0.0.0"; fi

  prompt_notes
  confirm_release "$full_version" "$v_name" "$min_version"
  check_env
  build_apk
  build_aab
  update_backend "$v_name" "$min_version"   # 先設版本（決定 APK 檔名）
  upload_apk                                 # 再上傳 APK 檔
  git_tag "$v_name"
  print_summary "$v_name"
}

main
