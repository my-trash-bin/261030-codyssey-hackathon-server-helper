#!/usr/bin/env sh
# 호스트에서 ssh/scp/rsync 를 컨테이너(VPN) 경유로 바로 쓰도록 ssh config 를 만든다.
# .env 의 서버 IP/계정/포트를 읽어 hack-general / hack-gpu 두 항목을 생성한다.
#
#   gen-ssh-config.sh            # 설정을 출력하고 ./ssh_config 에도 저장
#   gen-ssh-config.sh install    # ~/.ssh/config 에 마커 블록으로 추가/갱신 (-F 불필요)
#   gen-ssh-config.sh uninstall  # ~/.ssh/config 에서 그 블록 제거
set -eu

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[ -f .env ] || { echo ".env 가 없습니다. cp .env.example .env 후 값을 채우세요." >&2; exit 1; }

# .env 로드 (IP/USER/PORT 만 사용; 비밀번호는 출력하지 않는다)
set -a; . ./.env; set +a

PROXY="$ROOT/tools/ssh-proxy.sh"
KH="$ROOT/known_hosts"
BEGIN="# >>> hackathon ssh (gen-ssh-config.sh) >>>"
END="# <<< hackathon ssh <<<"

gen() {
  cat <<EOF
$BEGIN
# VPN을 쥔 컨테이너를 ProxyCommand 로 경유합니다. 최초 연결 때 OTP 를 한 번 물어봅니다.
# 서버는 비밀번호 인증이라 접속 시 비밀번호를 입력합니다(.env 의 *_PASSWORD).
Host hack-general
    HostName ${GENERAL_IP:-SET_GENERAL_IP}
    User ${GENERAL_USER:-ncloud}
    Port ${GENERAL_SSH_PORT:-22}
    ProxyCommand sh "$PROXY" %h %p
    StrictHostKeyChecking accept-new
    UserKnownHostsFile "$KH"
    PreferredAuthentications password,keyboard-interactive,publickey

Host hack-gpu
    HostName ${GPU_IP:-SET_GPU_IP}
    User ${GPU_USER:-ncloud}
    Port ${GPU_SSH_PORT:-22}
    ProxyCommand sh "$PROXY" %h %p
    StrictHostKeyChecking accept-new
    UserKnownHostsFile "$KH"
    PreferredAuthentications password,keyboard-interactive,publickey
$END
EOF
}

# ~/.ssh/config 에서 기존 마커 블록을 제거한 내용을 $1 에 쓴다.
strip_block() {
  awk -v b="$BEGIN" -v e="$END" '
    $0==b {skip=1}
    skip==0 {print}
    $0==e {skip=0}
  ' "$1"
}

case "${1:-}" in
  install)
    cfg="$HOME/.ssh/config"
    mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
    [ -f "$cfg" ] || : > "$cfg"
    chmod 600 "$cfg"
    tmp=$(mktemp)
    strip_block "$cfg" > "$tmp"
    # 끝 개행 보장 후 블록 추가
    [ -s "$tmp" ] && printf '\n' >> "$tmp"
    gen >> "$tmp"
    cp "$tmp" "$cfg"; rm -f "$tmp"
    echo ">> ~/.ssh/config 에 hack-general / hack-gpu 를 추가/갱신했습니다." >&2
    echo ">> 이제 -F 없이:" >&2
    echo "     ssh hack-gpu" >&2
    echo "     scp ./파일 hack-gpu:~/              # 어디서든 바로 업로드" >&2
    echo "     scp hack-gpu:~/결과.zip .           # 어디서든 바로 다운로드" >&2
    ;;
  uninstall)
    cfg="$HOME/.ssh/config"
    [ -f "$cfg" ] || { echo ">> ~/.ssh/config 가 없습니다." >&2; exit 0; }
    tmp=$(mktemp)
    strip_block "$cfg" > "$tmp"
    cp "$tmp" "$cfg"; rm -f "$tmp"
    echo ">> ~/.ssh/config 에서 hackathon 블록을 제거했습니다." >&2
    ;;
  ""|print)
    gen | tee "$ROOT/ssh_config"
    {
      echo ""
      echo ">> ./ssh_config 에도 저장했습니다. 사용법:"
      echo "     ssh -F ./ssh_config hack-gpu"
      echo "     scp -F ./ssh_config ./파일 hack-gpu:~/      # 어디서든 업로드"
      echo "     scp -F ./ssh_config hack-gpu:~/결과.zip .   # 어디서든 다운로드"
      echo "   매번 -F 가 귀찮으면:  (just|./hak) ssh-config install  → 'ssh hack-gpu' 로 끝"
    } >&2
    ;;
  *)
    echo "사용법: gen-ssh-config.sh [print|install|uninstall]" >&2; exit 2 ;;
esac
