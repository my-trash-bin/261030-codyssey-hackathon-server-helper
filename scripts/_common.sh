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
# NCP 공공존 SSL VPN은 OpenVPN 기반이며, 공식 Agent(ncurion-sa-client)와 동일한 2단계다:
#   ① POST /api/v3/authstate (type:"profile") → state 수신 + OTP(SMS/메일) 발송
#   ② POST /api/v3/profile   (state + OTP)     → 올바른 .ovpn(profile_body) 수신
# 받은 .ovpn 의 원격 포트(12000~13000)로 openvpn 터널을 붙이며, 같은 OTP 를 터널 인증에 쓴다.
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
  local cver="${VPN_CLIENT_VERSION:-1.1.4}"

  if ! { : < /dev/tty; } 2>/dev/null; then
    echo ">> VPN 연결에는 OTP 입력(터미널)이 필요합니다." >&2
    echo ">> 터미널에서 'just ssh-gpu'(또는 './hak ssh-gpu') 로 실행하세요." >&2
    return 1
  fi

  local base="https://${VPN_SERVER}:${VPN_PORT}"
  # prof(.ovpn)은 영속 볼륨(/data/vpn)에 저장. authf(아이디+OTP)는 1회용이라 ephemeral(/run/vpn).
  local prof=/data/vpn/profile.ovpn authf=/run/vpn/auth log=/var/log/vpn.log
  mkdir -p /data/vpn /run/vpn; chmod 700 /data/vpn /run/vpn

  # v3 API 호출 (헤더 Api-Version:1). 공식 앱은 TLS 검증을 끄므로(NODE_TLS_REJECT_UNAUTHORIZED=0)
  # 기본 검증으로 먼저 시도하고, 빈 응답이면 -k(검증 생략)로 1회 폴백한다.
  _vpn_api() {
    local path="$1" data="$2" r
    r="$(curl -s -m 20 -H 'Content-Type: application/json' -H 'Api-Version: 1' \
          -X POST "${base}${path}" --data-binary "$data" 2>/dev/null)"
    [[ -z "$r" ]] && r="$(curl -sk -m 20 -H 'Content-Type: application/json' -H 'Api-Version: 1' \
          -X POST "${base}${path}" --data-binary "$data" 2>/dev/null)"
    printf '%s' "$r"
  }

  # ① authstate (type:"profile") → state + OTP 발송
  echo "" >&2
  echo ">> SSL-VPN 1차 인증 중 (ID/PW)..." >&2
  local resp
  resp="$(_vpn_api /api/v3/authstate "$(jq -nc --arg u "$VPN_ID" --arg p "$VPN_PW" --arg cv "$cver" \
    '{user_id:$u, passwd:$p, type:"profile", client_version:$cv, os_name:"linux", os_version:"docker"}')")"
  if [[ "$(printf '%s' "$resp" | jq -r '.success' 2>/dev/null)" != "true" ]]; then
    echo ">> 1차 인증 실패: $(printf '%s' "$resp" | jq -r '.err_msg // "알 수 없는 오류(ID/PW 확인)"' 2>/dev/null)" >&2
    return 1
  fi
  local state pbody
  state="$(printf '%s' "$resp" | jq -r '.state // ""' 2>/dev/null)"
  pbody="$(printf '%s' "$resp" | jq -r '.profile_body // ""' 2>/dev/null)"

  # OTP 입력 (state 가 있으면 2차 인증 필요)
  local otp=""
  if [[ -n "$state" ]]; then
    echo ">> 1차 인증 성공. 이메일/SMS로 받은 OTP 코드를 입력하고 Enter:" >&2
    IFS= read -r otp < /dev/tty
    [[ -z "$otp" ]] && { echo ">> OTP가 입력되지 않았습니다." >&2; return 1; }
  else
    echo ">> 1차 인증 성공 (OTP 불필요)." >&2
  fi

  # 프로필(.ovpn) 확보 우선순위:
  #   ① 사용자가 둔 로컬 파일(공식 앱에서 받은 것) → ② authstate 직수신(profile_body)
  #   → ③ /api/v3/profile 다운로드 (state + OTP)
  local localprof="${VPN_PROFILE:-/work/transfer/naver-vpn.ovpn}"
  if [[ -s "$localprof" ]]; then
    cp "$localprof" "$prof"; echo ">> 로컬 프로필 사용: $localprof" >&2
  elif [[ "${VPN_REFRESH:-0}" != "1" && -s "$prof" ]]; then
    echo ">> 저장된 프로필 재사용: $prof  (새로 받으려면 VPN_REFRESH=1 또는 'just remove')" >&2
  elif [[ -n "$pbody" && "$pbody" != "null" ]]; then
    printf '%s' "$pbody" | base64 -d > "$prof" 2>/dev/null || printf '%s' "$pbody" | base64 -di > "$prof" 2>/dev/null \
      || { echo ">> 프로필 디코드 실패" >&2; return 1; }
    echo ">> 프로필 수신 완료." >&2
  else
    echo ">> 프로필 다운로드 중 (/api/v3/profile)..." >&2
    local resp2 pbody2 pname
    resp2="$(_vpn_api /api/v3/profile "$(jq -nc --arg u "$VPN_ID" --arg o "$otp" --arg s "$state" --arg cv "$cver" \
      '{user_id:$u, auth_type:1, otp_passwd:$o, state:$s, client_version:$cv, os_name:"linux", os_version:"docker"}')")"
    if [[ "$(printf '%s' "$resp2" | jq -r '.success' 2>/dev/null)" != "true" ]]; then
      echo ">> 프로필 다운로드 실패: $(printf '%s' "$resp2" | jq -r '.err_msg // "알 수 없는 오류"' 2>/dev/null)" >&2
      echo ">> (OTP가 틀렸거나 만료됐을 수 있습니다. 다시 접속을 시도하세요.)" >&2
      return 1
    fi
    pbody2="$(printf '%s' "$resp2" | jq -r '.profile_body // ""')"
    pname="$(printf '%s' "$resp2" | jq -r '.profile_name // "profile"')"
    if [[ -z "$pbody2" || "$pbody2" == "null" ]]; then echo ">> 응답에 프로필이 없습니다." >&2; return 1; fi
    printf '%s' "$pbody2" | base64 -d > "$prof" 2>/dev/null || printf '%s' "$pbody2" | base64 -di > "$prof" 2>/dev/null \
      || { echo ">> 프로필 디코드 실패" >&2; return 1; }
    echo ">> 프로필 저장: $pname" >&2
  fi

  # 벤더 프로필은 구버전 openvpn 기준이라 2.6 에서 제거된 지시어가 있을 수 있다.
  # 해당 줄을 주석 처리해 파싱 에러를 막는다(예: keysize 는 2.6 에서 제거됨).
  local _removed='keysize ncp-disable tls-remote max-routes ns-cert-type key-method'
  local _re; _re="$(printf '%s' "$_removed" | tr ' ' '|')"
  sed -i -E "s/^[[:space:]]*(${_re})([[:space:]].*)?\$/# [removed-for-openvpn2.6] &/" "$prof" 2>/dev/null || true

  # openvpn 터널 인증: 아이디 + OTP(없으면 비밀번호). 연결 후 authf 삭제.
  umask 077
  if [[ -n "$otp" ]]; then printf '%s\n%s\n' "$VPN_ID" "$otp" > "$authf"
  else printf '%s\n%s\n' "$VPN_ID" "$VPN_PW" > "$authf"; fi

  echo ">> OpenVPN 터널 연결 중..." >&2
  : > "$log"
  openvpn --config "$prof" --auth-user-pass "$authf" --auth-nocache --reneg-sec 0 \
    --allow-compression yes \
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
