#!/usr/bin/env bash
# 이 PC의 gh 인증으로 SSH 서버의 Git 커밋을 GitHub에 푸시합니다.
set -euo pipefail

usage() {
  echo '사용법: ./push.sh [SSH호스트] [원격저장소경로] [GitHubURL] [브랜치]'
  echo '기본값: remote-sub-1 /home/mjy/tmp https://github.com/my-trash-bin/261030-codyssey-hackathon-server-helper.git main'
  echo 'gh에 로그인된 PC에서 실행하세요. 커밋되지 않은 변경은 포함하지 않습니다.'
}

case "${1:-}" in -h|--help) usage; exit 0 ;; esac
if (( $# > 4 )); then usage >&2; exit 2; fi

source_host="${1:-remote-sub-1}"
source_path="${2:-/home/mjy/tmp}"
target_url="${3:-https://github.com/my-trash-bin/261030-codyssey-hackathon-server-helper.git}"
branch="${4:-main}"

for tool in git ssh gh; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "필요한 명령을 설치하세요: $tool" >&2
    exit 1
  }
done
git check-ref-format --branch "$branch" >/dev/null
gh auth status --hostname github.com >/dev/null

task_repo=$(mktemp -d "${TMPDIR:-/tmp}/server-helper-push.XXXXXX")
trap 'rm -rf -- "$task_repo"' EXIT

# 인증 정보는 이 PC에만 두고 SSH로 Git 이력만 가져옵니다.
git clone --bare --single-branch --branch "$branch" -- \
  "$source_host:$source_path" "$task_repo/repo.git"
git -C "$task_repo/repo.git" \
  -c credential.helper= -c 'credential.helper=!gh auth git-credential' \
  push -- "$target_url" "refs/heads/$branch:refs/heads/$branch"

echo "푸시 완료: $target_url ($branch)"
