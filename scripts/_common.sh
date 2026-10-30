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

# ── VPN 자동 연결 (OpenVPN / NCP v3 API) ──────────────────────
# NCP 공공존 SSL VPN은 OpenVPN 기반이다. :8443 은 인증 포털 API(/api/v3/authstate),
# 실제 터널은 응답으로 받은 .ovpn 프로필의 원격 포트(12000~13000)로 붙는다.
# 흐름: ID/PW 로 authstate 호출 → 성공 시 SMS OTP 발송 + .ovpn(base64) 수신
#       → 아이디+OTP 로 openvpn 인증.
# tun 인터페이스 존재 = VPN 연결됨으로 판단.
_vpn_up() { ip -o link show type tun 2>/dev/null | grep -q .; }
_vpn_dev() { ip -o link show type tun 2>/dev/null | awk -F': ' 'NR==1{sub(/@.*/,"",$2); print $2}'; }

# 대상 IP가 VPN(tun)으로 라우팅되도록 보장 (스플릿 터널 보완).
_vpn_route() {
  local ip="${1:-}" dev
  [[ -z "$ip" ]] && return 0
  dev="$(_vpn_dev)"; [[ -z "$dev" ]] && return 0
  ip route get "$ip" 2>/dev/null | grep -q "dev $dev" && return 0
  ip route add "$ip" dev "$dev" 2>/dev/null || true
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
  local ovpn_name="${VPN_OVPN_NAME:-vpn2033.ovpn}"

  if ! { : < /dev/tty; } 2>/dev/null; then
    echo ">> VPN 연결에는 OTP 입력(터미널)이 필요합니다." >&2
    echo ">> 터미널에서 'just ssh-gpu'(또는 './hak ssh-gpu') 로 실행하세요." >&2
    return 1
  fi

  local api="https://${VPN_SERVER}:${VPN_PORT}/api/v3/authstate"
  # prof(.ovpn)은 영속 볼륨(/data/vpn)에 저장 → shutdown 후에도 재사용. ('remove' 시 삭제)
  # authf(아이디+OTP)는 1회용이라 ephemeral(/run/vpn)에 두고 연결 후 즉시 삭제.
  local prof=/data/vpn/profile.ovpn authf=/run/vpn/auth log=/var/log/vpn.log
  mkdir -p /data/vpn /run/vpn; chmod 700 /data/vpn /run/vpn

  local mac
  mac="$(ip -o link show 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="link/ether"){m=$(i+1); gsub(":","-",m); print toupper(m); exit}}')"
  [[ -z "$mac" ]] && mac="00-00-00-00-00-00"

  local body resp
  body="$(jq -nc --arg u "$VPN_ID" --arg p "$VPN_PW" --arg o "$ovpn_name" --arg m "$mac" \
    '{user_id:$u, passwd:$p, type:"connect", ovpn_file_name:$o, client_version:"1.1.3", os_name:"linux", os_version:"docker", mac:[$m]}')"

  echo "" >&2
  echo ">> SSL-VPN 1차 인증 중 (ID/PW)..." >&2
  resp="$(curl -s -m 20 -H 'Content-Type: application/json' -H 'Api-Version: 1' \
    -X POST "$api" --data-binary "$body")"

  if [[ "$(printf '%s' "$resp" | jq -r '.success' 2>/dev/null)" != "true" ]]; then
    echo ">> 1차 인증 실패: $(printf '%s' "$resp" | jq -r '.err_msg // "알 수 없는 오류(응답 파싱 실패)"' 2>/dev/null)" >&2
    return 1
  fi

  # 프로필(.ovpn) 확보 우선순위:
  #   ① 사용자가 둔 로컬 파일(공식 앱에서 받은 것) → ② 이전에 저장해 둔 프로필(볼륨)
  #   → ③ authstate 응답의 profile_body (받으면 볼륨에 저장해 다음부터 재사용)
  local localprof="${VPN_PROFILE:-/work/transfer/naver-vpn.ovpn}" pbody
  if [[ -s "$localprof" ]]; then
    cp "$localprof" "$prof"
    echo ">> 로컬 프로필 사용: $localprof" >&2
  elif [[ -s "$prof" ]]; then
    echo ">> 저장된 프로필 재사용: $prof  (초기화하려면 'just remove')" >&2
  else
    pbody="$(printf '%s' "$resp" | jq -r '.profile_body // ""')"
    if [[ -z "$pbody" ]]; then
      echo ">> 서버가 프로필(.ovpn)을 주지 않았습니다. 서버 메시지:" >&2
      echo "   $(printf '%s' "$resp" | jq -r '.err_msg // "(없음)"' 2>/dev/null)" >&2
      echo ">> 해결: .env 의 VPN_OVPN_NAME 을 이 테넌트의 올바른 프로필(예: vpn<번호>.ovpn)로 바꾸세요." >&2
      echo ">> (번호는 운영진에게 'SSL-VPN 프로필/서버 번호' 로 문의. 또는 공식 앱에서 받은 .ovpn 파일을" >&2
      echo ">>  ./transfer/naver-vpn.ovpn 로 두면 그대로 사용합니다.)" >&2
      return 1
    fi
    printf '%s' "$pbody" | base64 -d > "$prof" 2>/dev/null || \
      printf '%s' "$pbody" | base64 -di > "$prof" 2>/dev/null || \
      { echo ">> 프로필 디코드 실패" >&2; return 1; }
    echo ">> 프로필을 저장했습니다(다음부터 재사용): $prof" >&2
  fi

  local otp
  echo ">> 1차 인증 성공. 이메일/SMS로 받은 OTP 코드를 입력하고 Enter:" >&2
  IFS= read -r otp < /dev/tty
  if [[ -z "$otp" ]]; then echo ">> OTP가 입력되지 않았습니다." >&2; return 1; fi

  umask 077
  printf '%s\n%s\n' "$VPN_ID" "$otp" > "$authf"

  echo ">> OpenVPN 터널 연결 중..." >&2
  : > "$log"
  openvpn --config "$prof" --auth-user-pass "$authf" --auth-nocache --reneg-sec 0 \
    --daemon --log "$log" --writepid /run/vpn.pid

  local i
  for i in $(seq 1 60); do
    if grep -q "Initialization Sequence Completed" "$log" 2>/dev/null && _vpn_up; then
      rm -f "$authf"
      sleep 1; _vpn_route "$ip"
      echo ">> VPN 연결됨." >&2
      return 0
    fi
    if grep -qiE "AUTH_FAILED|auth-failure|Exiting due to fatal error" "$log" 2>/dev/null; then
      rm -f "$authf"
      echo ">> OpenVPN 인증/연결 실패. 최근 로그:" >&2; tail -n 20 "$log" >&2; return 1
    fi
    sleep 1
  done
  rm -f "$authf"
  echo ">> VPN 연결 시간 초과. 최근 로그:" >&2; tail -n 25 "$log" >&2; return 1
}
