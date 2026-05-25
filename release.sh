#!/bin/bash
# =============================================================================
#  TekSwing 推版腳本
#  用法：
#    ./release.sh                            ← 互動式
#    ./release.sh -n "修正 bug" -n "新功能"  ← 帶更新說明
#    ./release.sh --force -n "重要更新"      ← 強制更新
#    ./release.sh --min 1.1.0               ← 指定最低支援版本
#    ./release.sh --dry-run                 ← 模擬，不實際 build / 上傳
# =============================================================================
set -euo pipefail

# ── ① 設定區（只需改這裡）────────────────────────────────────────────────────
ADMIN_KEY="change-this-admin-secret-in-production"   # ← 改成正式密鑰
API_BASE="https://tekswing.api.atk.tw"

B2_KEY_ID="005cdd4425aa9cd0000000003"
B2_APP_KEY="K005l60DuFwoMdfpAWLq8Hr5Wq47hR8"
B2_BUCKET="tekswing"
B2_ENDPOINT="https://s3.us-east-005.backblazeb2.com"
APK_REMOTE_DIR="releases/android"          # B2 bucket 內的路徑

# APK 下載 URL 格式（B2 S3 compatible，bucket 需設為 Public）
# 若 bucket 為 Private，改用你自己的代理下載端點
DOWNLOAD_BASE="https://s3.us-east-005.backblazeb2.com/${B2_BUCKET}"

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
MIN_VERSION=""
RELEASE_NOTES=()

usage() {
  echo ""
  echo -e "${BOLD}TekSwing 推版腳本${NC}"
  echo ""
  echo "用法: $0 [選項]"
  echo ""
  echo "選項:"
  echo "  -n, --note <文字>    新增更新說明（可重複）"
  echo "  -f, --force          強制更新（使用者必須更新才能繼續）"
  echo "  -m, --min <版本>     最低支援版本（預設保持不變）"
  echo "      --dry-run        模擬執行，不實際 build 或上傳"
  echo "  -h, --help           顯示說明"
  echo ""
  echo "範例:"
  echo "  $0 -n '新增設定頁面' -n '修正畫質選擇問題'"
  echo "  $0 --force -n '重要安全更新' --min 1.1.0"
  echo ""
  exit 0
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -f|--force)   FORCE_UPDATE=true; shift ;;
    --dry-run)    DRY_RUN=true; shift ;;
    -n|--note)    RELEASE_NOTES+=("$2"); shift 2 ;;
    -m|--min)     MIN_VERSION="$2"; shift 2 ;;
    -h|--help)    usage ;;
    *) echo -e "${RED}未知參數: $1${NC}"; usage ;;
  esac
done

# ── ③ 工具函式 ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBSPEC="$SCRIPT_DIR/pubspec.yaml"

read_pubspec_version() {
  grep '^version:' "$PUBSPEC" | sed 's/version:[[:space:]]*//' | tr -d '[:space:]'
}

version_name() { echo "$1" | cut -d'+' -f1; }   # "1.1.0+2" → "1.1.0"

check_cmd() {
  command -v "$1" &>/dev/null || print_err "$1 未安裝。$2"
}

# ── ④ 環境檢查 ────────────────────────────────────────────────────────────────
check_env() {
  print_header "環境檢查"
  check_cmd flutter  "請先安裝 Flutter SDK"
  check_cmd aws      "請安裝 AWS CLI：pip install awscli 或 brew install awscli"
  check_cmd curl     "請先安裝 curl"
  check_cmd jq       "請安裝 jq：brew install jq 或 sudo apt install jq"

  print_ok "flutter $(flutter --version 2>/dev/null | head -1 | awk '{print $2}')"
  print_ok "aws CLI $(aws --version 2>&1 | awk '{print $1}')"
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
  echo -e "  │  ${BOLD}更新說明${NC}"
  for note in "${RELEASE_NOTES[@]}"; do
    echo -e "  │    • $note"
  done
  if [ "$DRY_RUN" = true ]; then
    echo -e "  │  ${YELLOW}[DRY RUN] 不會實際 build / 上傳 / 呼叫 API${NC}"
  fi
  echo -e "  └─────────────────────────────────────────────"
  echo ""
  read -r -p "  確認推版？(y/N) " confirm
  [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { print_warn "已取消"; exit 0; }
}

# ── ⑦ Flutter Build ──────────────────────────────────────────────────────────
build_apk() {
  print_header "Build Release APK"
  local apk_path="$SCRIPT_DIR/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"

  if [ "$DRY_RUN" = true ]; then
    print_warn "[dry-run] 跳過 flutter build"
    echo "$apk_path"
    return
  fi

  print_info "flutter build apk --release --split-per-abi"
  # 顯示最後幾行 build log
  if flutter build apk --release --split-per-abi 2>&1 | tail -8; then
    [ -f "$apk_path" ] || print_err "找不到 APK：$apk_path"
    local size_mb
    size_mb=$(du -m "$apk_path" | cut -f1)
    print_ok "Build 完成（${size_mb} MB）：$apk_path"
  else
    print_err "flutter build 失敗，請檢查上方錯誤訊息"
  fi

  echo "$apk_path"
}

# ── ⑧ 上傳 B2 ────────────────────────────────────────────────────────────────
upload_b2() {
  local apk_path="$1" v_name="$2"
  print_header "上傳 APK 到 B2"

  local remote_key="${APK_REMOTE_DIR}/app-${v_name}.apk"
  local download_url="${DOWNLOAD_BASE}/${remote_key}"

  if [ "$DRY_RUN" = true ]; then
    print_warn "[dry-run] 跳過上傳"
    print_info "下載 URL 將為：$download_url"
    echo "$download_url"
    return
  fi

  print_info "上傳至 s3://$B2_BUCKET/$remote_key ..."
  AWS_ACCESS_KEY_ID="$B2_KEY_ID" \
  AWS_SECRET_ACCESS_KEY="$B2_APP_KEY" \
  aws s3 cp "$apk_path" "s3://$B2_BUCKET/$remote_key" \
    --endpoint-url "$B2_ENDPOINT" \
    --no-progress \
    --content-type "application/vnd.android.package-archive"

  print_ok "上傳完成"
  print_info "下載 URL：${CYAN}$download_url${NC}"
  echo "$download_url"
}

# ── ⑨ 呼叫後端 Admin API ─────────────────────────────────────────────────────
update_backend() {
  local v_name="$1" min_ver="$2" download_url="$3"
  print_header "更新後端版本設定"

  local today
  today=$(date +%Y-%m-%d)

  # 將 bash array 轉成 JSON array
  local notes_json
  notes_json=$(printf '%s\n' "${RELEASE_NOTES[@]}" | jq -R . | jq -s .)

  local payload
  payload=$(jq -n \
    --arg     latest "$v_name" \
    --arg     min    "$min_ver" \
    --argjson force  "$FORCE_UPDATE" \
    --arg     url    "$download_url" \
    --argjson notes  "$notes_json" \
    --arg     date   "$today" \
    '{
      latestVersion:      $latest,
      minRequiredVersion: $min,
      forceUpdate:        $force,
      updateUrl:          $url,
      releaseNotes:       $notes,
      releaseDate:        $date
    }')

  if [ "$DRY_RUN" = true ]; then
    print_warn "[dry-run] 跳過 API 呼叫"
    echo "  Payload: $payload"
    return
  fi

  print_info "PUT $API_BASE/api/admin/app/version/android"

  local resp http_code body
  resp=$(curl -s -w "\n%{http_code}" -X PUT \
    "$API_BASE/api/admin/app/version/android" \
    -H "Content-Type: application/json" \
    -H "X-Admin-Key: $ADMIN_KEY" \
    -d "$payload" \
    --max-time 15)

  http_code=$(echo "$resp" | tail -1)
  body=$(echo "$resp" | head -n -1)

  if [ "$http_code" = "200" ]; then
    print_ok "後端版本設定已更新"
    # 顯示回傳的版本資訊
    echo "$body" | jq -r '
      "  版本：\(.data.latestVersion)  最低：\(.data.minRequiredVersion)  強制：\(.data.forceUpdate)"
    ' 2>/dev/null || true
  else
    print_err "API 回應 $http_code\n  回應內容：$body"
  fi
}

# ── ⑩ Git Tag ────────────────────────────────────────────────────────────────
git_tag() {
  local v_name="$1"
  print_header "Git Tag"
  local tag="v$v_name"

  if [ "$DRY_RUN" = true ]; then
    print_warn "[dry-run] 跳過 git tag $tag"
    return
  fi

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
  local v_name="$1" download_url="$2"
  print_header "推版完成 🎉"
  echo -e "  版本：   ${BOLD}v$v_name${NC}"
  echo -e "  APK URL：${CYAN}$download_url${NC}"
  echo -e "  強制更新：$([ "$FORCE_UPDATE" = true ] && echo -e "${RED}是${NC}" || echo '否')"
  echo ""
  echo -e "  ${GREEN}✓  所有用戶下次開啟 App 將收到更新提示。${NC}"
  echo ""
}

# ── 主流程 ───────────────────────────────────────────────────────────────────
main() {
  print_header "TekSwing 推版腳本"

  # 讀版本
  local full_version v_name
  full_version=$(read_pubspec_version)
  v_name=$(version_name "$full_version")

  # 最低支援版本預設與目前相同（或由參數指定）
  local min_version="${MIN_VERSION:-$v_name}"

  # 取得更新說明
  prompt_notes

  # 確認
  confirm_release "$full_version" "$v_name" "$min_version"

  # 環境
  check_env

  # Build
  local apk_path
  apk_path=$(build_apk)

  # 上傳
  local download_url
  download_url=$(upload_b2 "$apk_path" "$v_name")

  # 後端
  update_backend "$v_name" "$min_version" "$download_url"

  # Git tag
  git_tag "$v_name"

  # 摘要
  print_summary "$v_name" "$download_url"
}

main
