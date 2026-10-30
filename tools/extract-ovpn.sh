#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
# 공식 SSL VPN 클라이언트가 저장해 둔 .ovpn 프로필을 찾아 transfer/ 로 추출합니다.
#
#  .ovpn 프로필은 계정(테넌트)마다 다를 수 있어 저장소에 포함하지 않습니다.
#  각자 공식 클라이언트로 한 번 로그인한 뒤, 이 스크립트로 자신의 프로필을 꺼냅니다.
#
#  흐름:
#    1) 공식 NAVER Cloud SSL VPN 클라이언트(macOS/Windows/Linux 앱)로 "한 번" 로그인
#       (ID/PW/OTP + 메뉴에서 해커톤 서버 선택) → 앱이 .ovpn 을 저장함
#    2) 이 스크립트 실행 → 그 .ovpn 을 찾아 transfer/naver-vpn.ovpn 로 복사하고
#       프로필 번호(.env 의 VPN_OVPN_NAME 에 넣을 값)를 출력
#
#  사용:
#    tools/extract-ovpn.sh               # 자동 탐색 → 최신 프로필 복사
#    tools/extract-ovpn.sh <경로.ovpn>   # 특정 .ovpn 파일 지정
#    OUT=~/my.ovpn tools/extract-ovpn.sh # 저장 위치 지정
#
#  (just get-ovpn / ./hak get-ovpn 으로도 실행됩니다. 컨테이너가 아니라 호스트에서 동작.)
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

# 저장소 루트 기준으로 동작 (어디서 호출하든)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 저장 위치 결정 (기본: transfer/naver-vpn.ovpn)
if [ -n "${OUT:-}" ]; then OUT="${OUT/#\~/$HOME}"
elif [ -d transfer ]; then OUT="transfer/naver-vpn.ovpn"
else OUT="naver-vpn.ovpn"; fi

# 수정시각(epoch) — GNU(stat -c)와 BSD/macOS(stat -f) 모두 대응
mtime() { stat -f '%m' "$1" 2>/dev/null || stat -c '%Y' "$1" 2>/dev/null || echo 0; }
mwhen() {
  stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$1" 2>/dev/null \
    || date -d "@$(mtime "$1")" '+%Y-%m-%d %H:%M' 2>/dev/null \
    || date -r "$(mtime "$1")" '+%Y-%m-%d %H:%M' 2>/dev/null \
    || echo '?'
}

copy_and_report() {
  local src="$1"
  [ -n "$(dirname "$OUT")" ] && mkdir -p "$(dirname "$OUT")"
  cp "$src" "$OUT"
  echo
  echo "✅ 추출 완료"
  echo "   원본 : $src"
  echo "   저장 : $OUT   (gitignore 대상이라 커밋되지 않음)"
  echo "   번호 : VPN_OVPN_NAME=$(basename "$src")   (.env 에 넣어두면 파일 없이도 재사용)"
  echo "   ── remote/포트 라인:"
  grep -iE '^(remote|port|proto) ' "$src" | sed 's/^/        /' || true
  echo
  echo "이제 접속하면 이 프로필을 자동 사용합니다:"
  echo "   just ssh-gpu        (또는 ./hak ssh-gpu)"
}

# 1) 인자로 특정 .ovpn 을 주면 그걸 사용
if [ "${1:-}" != "" ]; then
  SRC="${1/#\~/$HOME}"
  [ -f "$SRC" ] || { echo "파일이 없습니다: $SRC" >&2; exit 1; }
  copy_and_report "$SRC"; exit 0
fi

# 2) 공식 앱이 저장하는 위치들을 탐색 (macOS + Linux + Windows/WSL)
echo ">> 공식 클라이언트가 저장한 .ovpn 을 탐색합니다..."
ROOTS=(
  # macOS
  "$HOME/Library/Application Support/ncurion-sa-client"
  "$HOME/Library/Application Support"
  "$HOME/Library/Containers"
  # Linux (Electron 기본 config 경로)
  "$HOME/.config/ncurion-sa-client"
  "$HOME/.config"
  "$HOME/.ncurion"
  # Windows(WSL 등)에서 마운트된 경우
  "$HOME/AppData/Roaming/ncurion-sa-client"
)

TMPLIST="$(mktemp)"; trap 'rm -f "$TMPLIST"' EXIT
for r in "${ROOTS[@]}"; do
  [ -d "$r" ] || continue
  case "$r" in
    *ncurion-sa-client|*/.ncurion)
      # 전용 경로는 그대로 전부
      find "$r" -maxdepth 8 -type f -name '*.ovpn' 2>/dev/null ;;
    *)
      # 공용 경로는 'ncurion' 하위만 (오탐 방지)
      find "$r" -maxdepth 8 -type f -name '*.ovpn' -path '*ncurion*' 2>/dev/null ;;
  esac
done | sort -u > "$TMPLIST"

# 전용 경로에서 못 찾으면, vpn####.ovpn 패턴을 넓게 한 번 더
if [ ! -s "$TMPLIST" ]; then
  for base in "$HOME/Library/Application Support" "$HOME/Library/Containers" "$HOME/.config"; do
    [ -d "$base" ] && find "$base" -maxdepth 8 -type f -name 'vpn*.ovpn' 2>/dev/null
  done | sort -u > "$TMPLIST" || true
fi

if [ ! -s "$TMPLIST" ]; then
  echo
  echo "⚠️  저장된 .ovpn 을 못 찾았습니다. 아래를 확인하세요:"
  echo "   1) 공식 SSL VPN 클라이언트를 설치했나요?"
  echo "      → NCP 공공 콘솔의 'SSL VPN' 메뉴에서 클라이언트 다운로드,"
  echo "        또는 운영진에게 클라이언트 링크 요청."
  echo "   2) 그 앱으로 실제로 '로그인'해서 해커톤 서버를 선택했나요?"
  echo "      (로그인에 성공해야 프로필이 생성·저장됩니다.)"
  echo
  echo "   앱 로그인 후 다시 실행하세요. 경로를 직접 알면:"
  echo "      tools/extract-ovpn.sh /경로/파일.ovpn"
  echo
  echo "   참고 - macOS 보통 저장 위치:"
  echo "      ~/Library/Application Support/ncurion-sa-client/vpn/profiles/"
  exit 1
fi

# 여러 개면 최신(수정시각) 것을 고르고, 전체 목록도 출력
echo ">> 찾은 프로필:"
BEST=""; BEST_T=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  t="$(mtime "$f")"
  echo "     [$(mwhen "$f")]  $f"
  if [ "${t:-0}" -gt "$BEST_T" ] 2>/dev/null; then BEST_T="$t"; BEST="$f"; fi
done < "$TMPLIST"

[ -n "$BEST" ] || BEST="$(head -n1 "$TMPLIST")"
echo ">> 최신 프로필을 사용합니다: $BEST"
copy_and_report "$BEST"
