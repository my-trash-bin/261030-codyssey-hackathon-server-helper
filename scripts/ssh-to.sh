#!/usr/bin/env bash
# 대상 서버로 대화형 SSH 터미널 세션을 연다.
#   ssh-to.sh <general|gpu> [원격명령...]
set -euo pipefail
source /opt/scripts/_common.sh
resolve_target "${1:-}"; shift || true

echo ">> ${LABEL}(${IP}:${PORT}) 로 ${USER_} 계정 접속" >&2
export SSHPASS="$PASS"
exec sshpass -e ssh "${SSH_OPTS[@]}" "${USER_}@${IP}" "$@"
