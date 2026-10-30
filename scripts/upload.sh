#!/usr/bin/env bash
# 로컬 파일/폴더를 서버로 업로드한다 (rsync over SSH).
#   upload.sh <general|gpu> <로컬경로> [원격경로(기본: ~/)]
# 로컬경로는 컨테이너 기준이며, 호스트의 ./transfer 가 /work/transfer 로 보입니다.
set -euo pipefail
source /opt/scripts/_common.sh
resolve_target "${1:-}"; shift || true

SRC="${1:?업로드할 로컬 경로를 지정하세요}"; shift || true
DEST="${1:-~/}"

if [[ ! -e "$SRC" ]]; then
  echo "로컬 경로가 없습니다: $SRC" >&2
  echo "(호스트의 ./transfer 폴더에 파일을 두면 컨테이너에서 /work/transfer 로 보입니다)" >&2
  exit 2
fi

echo ">> 업로드: $SRC → ${LABEL}:${DEST}" >&2
export SSHPASS="$PASS"
exec rsync -avz --progress \
  -e "sshpass -e ssh ${SSH_OPTS[*]}" \
  "$SRC" "${USER_}@${IP}:${DEST}"
