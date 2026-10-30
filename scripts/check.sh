#!/usr/bin/env bash
# VPN 연결 후 각 서버의 SSH 포트 도달 여부를 점검한다.
#   check.sh [general|gpu]   (인자 없으면 둘 다)
set -euo pipefail
source /opt/scripts/_common.sh

check_one() {
  resolve_target "$1"
  printf '%-10s %s:%s ... ' "$LABEL" "$IP" "$PORT"
  if nc -z -w 5 "$IP" "$PORT" 2>/dev/null; then
    echo "OK (포트 열림)"
  else
    echo "실패 (VPN 연결/사설IP/포트 확인)"
  fi
}

if [[ -n "${1:-}" ]]; then
  check_one "$1"
else
  check_one general || true
  check_one gpu || true
fi
