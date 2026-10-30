#!/usr/bin/env bash
# 컨테이너를 살아있게 유지. VPN 연결과 SSH는 exec로 실행한다.
set -euo pipefail
mkdir -p /root/.ssh /work/transfer
chmod 700 /root/.ssh
touch /root/.ssh/known_hosts

cat <<'EOF'
┌───────────────────────────────────────────────────────────┐
│  hackathon-access 컨테이너 준비 완료                        │
│                                                           │
│  1) VPN 연결 :  make vpn        (OTP 입력, 터미널 유지)     │
│  2) 터미널   :  make ssh-gpu  /  make ssh-general          │
│  3) 업로드   :  make upload-gpu FILE=...                   │
│  4) 다운로드 :  make download-gpu REMOTE=...               │
└───────────────────────────────────────────────────────────┘
EOF

exec sleep infinity
