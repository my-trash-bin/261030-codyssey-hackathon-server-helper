#!/usr/bin/env bash
# ProxyCommand 사전 단계: 대상 IP 로 VPN 연결을 보장한다(필요 시 OTP 입력).
# tun 이 이미 떠 있으면 즉시 반환. 호스트의 ssh-proxy.sh 가 nc 중계 직전에 호출한다.
#   ensure-vpn.sh [대상IP]
set -euo pipefail
source /opt/scripts/_common.sh
ensure_vpn "${1:-}"
