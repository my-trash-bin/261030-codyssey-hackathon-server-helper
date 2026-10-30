#!/usr/bin/env bash
# VPN 연결을 끊는다 (재인증/OTP 재입력이 필요할 때).
set -euo pipefail
if pkill -f 'openconnect' 2>/dev/null; then
  echo ">> VPN 연결을 종료했습니다."
else
  echo ">> 실행 중인 VPN이 없습니다."
fi
rm -f /run/vpn.pid 2>/dev/null || true
