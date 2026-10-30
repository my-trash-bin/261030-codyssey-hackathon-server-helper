#!/usr/bin/env bash
# SSL-VPN 연결 (컨테이너 내부에서 포그라운드로 유지).
# OTP는 실행 중 터미널에서 직접 입력한다. 연결을 끊으려면 Ctrl+C.
set -euo pipefail

: "${VPN_SERVER:?VPN_SERVER가 .env에 없습니다}"
: "${VPN_PORT:=8443}"
: "${VPN_ID:?VPN_ID가 .env에 없습니다}"
: "${VPN_PW:?VPN_PW가 .env에 없습니다}"

echo ">> SSL-VPN 연결: ${VPN_SERVER}:${VPN_PORT} (ID: ${VPN_ID})"
echo ">> OTP 코드를 요청하면 이메일/SMS로 받은 코드를 입력하세요. 끊으려면 Ctrl+C."
echo

# openfortivpn는 Fortinet 계열 SSL-VPN용 CLI 클라이언트입니다.
# 공공존 게이트웨이가 Fortinet 호환이 아닐 경우, 공식 NAVER Cloud SSL VPN
# Agent(호스트)로 먼저 연결한 뒤 이 토이킷의 --network 모드를 사용하세요.
exec openfortivpn "${VPN_SERVER}:${VPN_PORT}" \
  --username="${VPN_ID}" \
  --password="${VPN_PW}" \
  --otp-prompt="token" \
  --persistent=5
