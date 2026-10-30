#!/usr/bin/env bash
# 서버의 파일/폴더를 로컬로 내려받는다 (rsync over SSH).
#   download.sh <general|gpu> <원격경로> [로컬경로(기본: /work/transfer/)]
# 로컬 기본 경로(/work/transfer)는 호스트의 ./transfer 폴더입니다.
set -euo pipefail
source /opt/scripts/_common.sh
resolve_target "${1:-}"; shift || true

REMOTE="${1:?내려받을 원격 경로를 지정하세요}"; shift || true
DEST="${1:-/work/transfer/}"

echo ">> 다운로드: ${LABEL}:${REMOTE} → $DEST" >&2
export SSHPASS="$PASS"
exec rsync -avz --progress \
  -e "sshpass -e ssh ${SSH_OPTS[*]}" \
  "${USER_}@${IP}:${REMOTE}" "$DEST"
