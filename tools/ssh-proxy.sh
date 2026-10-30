#!/usr/bin/env sh
# SSH ProxyCommand: VPN을 쥔 컨테이너를 TCP 중계로 삼아 대상(%h %p)에 붙는다.
# 이렇게 하면 호스트에서 ssh/scp/rsync 를 "네이티브로" 그대로 쓸 수 있다.
# (직접 실행할 일은 없고, gen-ssh-config.sh 가 만든 ssh config 가 호출한다.)
#   ssh-proxy.sh <대상IP> <포트>
#
# stdout 은 ssh 가 데이터 채널로 쓰므로, 진단/프롬프트 출력은 전부 /dev/tty 로 보낸다.
set -eu

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

ip="${1:?대상 IP가 필요합니다}"
port="${2:?대상 포트가 필요합니다}"

if [ ! -f .env ]; then
  { echo "ssh-proxy: .env 가 없습니다 ($ROOT/.env). cp .env.example .env 후 값을 채우세요."; } >/dev/tty 2>/dev/null || true
  exit 1
fi

# 터미널이 있으면 대화형으로 컨테이너+VPN을 보장(OTP 입력 가능).
# 없으면(배치 등) 조용히 시도하되 실패해도 중계는 시도한다.
if { : </dev/tty; } 2>/dev/null; then
  docker compose up -d >/dev/tty 2>&1 || true
  # ensure-vpn: 실제 터미널(/dev/tty)을 stdin/stdout 으로 줘서 -t 와 OTP 입력이 되게 한다.
  docker compose exec -it access ensure-vpn.sh "$ip" >/dev/tty 2>&1 </dev/tty
else
  docker compose up -d >/dev/null 2>&1 || true
  docker compose exec -T access ensure-vpn.sh "$ip" >/dev/null 2>&1 || true
fi

# 데이터 채널: 컨테이너 안에서 대상으로 TCP 연결. stdio 는 ssh 가 쥔다(-T 로 pty 비활성).
exec docker compose exec -T access nc "$ip" "$port"
