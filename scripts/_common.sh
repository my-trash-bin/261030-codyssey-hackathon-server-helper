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
