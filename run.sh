#!/usr/bin/env bash
# 바로 접속: ./run.sh [gpu|general|hak 명령...]
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

case "${1:-gpu}" in
  -h|--help|help)
    echo '사용법: ./run.sh [gpu|general|hak 명령...]'
    echo '인자 없이 실행하면 GPU 서버에 접속합니다.'
    exit 0 ;;
  gpu|general)
    target="${1:-gpu}"
    if (( $# )); then shift; fi
    set -- "ssh-$target" "$@" ;;
esac

command -v docker >/dev/null 2>&1 || {
  echo 'Docker를 설치한 뒤 다시 실행하세요.' >&2
  exit 1
}
docker compose version >/dev/null

case "$1" in
  down|logs|vpn-stop) ;;
  *)
    if [[ ! -f .env ]]; then
      (umask 077; cp .env.example .env)
      echo '.env를 생성했습니다. VPN 계정과 접속할 서버의 IP/비밀번호를 입력하고 저장하세요.'
      if [[ ! -t 0 || ! -t 1 ]]; then
        echo '.env를 편집한 뒤 터미널에서 다시 실행하세요.' >&2
        exit 1
      fi
      read -r -a editor_cmd <<< "${VISUAL:-${EDITOR:-vi}}"
      "${editor_cmd[@]}" .env
    fi ;;
esac

exec ./hak "$@"
