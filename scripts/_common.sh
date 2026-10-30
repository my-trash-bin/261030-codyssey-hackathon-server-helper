#!/usr/bin/env bash
# 공통 로직: 대상 서버(general|gpu)의 접속 변수를 해석한다.
set -euo pipefail

resolve_target() {
  local t="${1:-}"
  case "$t" in
    gpu|GPU)
      HOST="${GPU_HOSTNAME:-}"; IP="${GPU_IP:-}"; USER_="${GPU_USER:-ncloud}"
      PASS="${GPU_PASSWORD:-}"; PORT="${GPU_SSH_PORT:-22}"; LABEL="GPU 서버" ;;
    general|GENERAL|gen)
      HOST="${GENERAL_HOSTNAME:-}"; IP="${GENERAL_IP:-}"; USER_="${GENERAL_USER:-ncloud}"
      PASS="${GENERAL_PASSWORD:-}"; PORT="${GENERAL_SSH_PORT:-22}"; LABEL="일반 서버" ;;
    *)
      echo "대상을 general 또는 gpu 로 지정하세요 (받은 값: '$t')" >&2; exit 2 ;;
  esac
  : "${PORT:=22}"
  if [[ -z "$IP" ]]; then
    echo "[$LABEL] IP가 .env에 설정되지 않았습니다." >&2; exit 2
  fi
  if [[ -z "$PASS" ]]; then
    echo "[$LABEL] 비밀번호가 .env에 설정되지 않았습니다." >&2; exit 2
  fi
  export HOST IP USER_ PASS PORT LABEL
  # 공통 SSH 옵션. known_hosts는 유지하되, 최초 접속은 자동 수락(TOFU).
  SSH_OPTS=(
    -p "$PORT"
    -o StrictHostKeyChecking=accept-new
    -o UserKnownHostsFile=/root/.ssh/known_hosts
    -o ConnectTimeout=15
    -o ServerAliveInterval=30
  )
}

# ── VPN 자동 연결 ─────────────────────────────────────────────
# ppp0 인터페이스 존재 = VPN 연결됨으로 판단.
_vpn_up() { ip link show ppp0 >/dev/null 2>&1; }

# 대상 IP가 VPN(ppp0)으로 라우팅되도록 보장 (스플릿 터널 보완).
_vpn_route() {
  local ip="${1:-}"
  [[ -z "$ip" ]] && return 0
  ip route get "$ip" 2>/dev/null | grep -q 'dev ppp0' && return 0
  ip route add "$ip" dev ppp0 2>/dev/null || true
}

# VPN이 안 올라와 있으면 올린다. 올라와 있으면 즉시 반환.
# 인자: 라우팅을 보장할 대상 IP (선택).
ensure_vpn() {
  local ip="${1:-}"
  if _vpn_up; then _vpn_route "$ip"; return 0; fi

  : "${VPN_SERVER:?VPN_SERVER가 .env에 없습니다}"
  : "${VPN_PORT:=8443}"
  : "${VPN_ID:?VPN_ID가 .env에 없습니다}"
  : "${VPN_PW:?VPN_PW가 .env에 없습니다}"

  if ! { : < /dev/tty; } 2>/dev/null; then
    echo ">> VPN 연결에는 OTP 입력(터미널)이 필요합니다." >&2
    echo ">> 터미널에서 'just ssh-gpu'(또는 './hak ssh-gpu') 로 실행하세요." >&2
    return 1
  fi

  local log=/var/log/vpn.log pidf=/run/vpn.pid pid
  echo "" >&2
  echo ">> SSL-VPN 미연결 → 연결을 시작합니다 (${VPN_SERVER}:${VPN_PORT})." >&2
  echo ">> 이메일/SMS로 받은 OTP 코드를 입력하고 Enter 를 누르세요." >&2

  # 컨테이너에 상주시킨다. stdin은 터미널(OTP 입력용), 로그는 파일로.
  # setsid로 제어 터미널에서 분리해야 백그라운드에서도 stdin을 읽을 수 있다.
  setsid openfortivpn "${VPN_SERVER}:${VPN_PORT}" \
    --username="${VPN_ID}" --password="${VPN_PW}" \
    --otp-prompt="token" --persistent=5 \
    >"$log" 2>&1 < /dev/tty &
  echo $! >"$pidf"
  pid="$(cat "$pidf")"

  local i
  for i in $(seq 1 90); do
    if _vpn_up; then
      sleep 1
      _vpn_route "$ip"
      echo ">> VPN 연결됨." >&2
      return 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      echo ">> VPN 연결 실패. 최근 로그:" >&2; tail -n 20 "$log" >&2; return 1
    fi
    sleep 1
  done
  echo ">> VPN 연결 시간 초과. 최근 로그:" >&2; tail -n 20 "$log" >&2; return 1
}
