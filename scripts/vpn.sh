#!/usr/bin/env bash
# (선택) VPN을 미리 연결해 둔다. ssh/upload/download 가 자동으로 연결하므로
# 보통은 쓸 필요가 없다. 재인증이 필요할 때 vpn-stop.sh 로 끊고 다시 붙인다.
set -euo pipefail
source /opt/scripts/_common.sh

if _vpn_up; then
  echo ">> 이미 VPN이 연결되어 있습니다."
else
  ensure_vpn ""
fi
