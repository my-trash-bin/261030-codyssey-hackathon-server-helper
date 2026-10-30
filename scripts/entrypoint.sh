#!/usr/bin/env bash
# 컨테이너를 살아있게 유지. VPN 연결과 SSH는 exec로 실행한다.
set -euo pipefail
mkdir -p /root/.ssh /work/transfer
chmod 700 /root/.ssh
touch /root/.ssh/known_hosts

echo ">> hackathon-access 컨테이너 준비 완료. host에서 'just ssh-gpu' 등으로 접속하세요."

exec sleep infinity
