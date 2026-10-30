# 2026 해커톤 서버 접속 토이킷 (just)
# just 가 없으면 동일 기능의 ./hak 셸 스크립트를 쓰세요.
#
# 사용 전 1회:  cp .env.example .env  후 값 입력
#
# 알아야 할 명령은 이게 전부입니다:
#   just ssh-gpu        just ssh-general        # 서버 접속
#   just upload-gpu <로컬> [원격]               # 업로드
#   just download-gpu <원격> [로컬]             # 다운로드
#   just shutdown                               # 종료(저장된 프로필은 유지)
#   just remove                                 # 종료 + 저장된 인증 정보까지 삭제
#   just get-ovpn                               # (최초 1회) 공식 앱의 .ovpn 추출
# (컨테이너 시작·VPN 연결은 자동. 최초 접속 때 OTP만 한 번 입력.
#  OTP는 1회용이라 저장 불가 — 컨테이너를 켜 두면 재입력 없이 계속 사용 가능)

_default:
    @just --list

# GPU 서버 터미널 접속
ssh-gpu: _up
    docker compose exec -it access ssh-to.sh gpu

# 일반 서버 터미널 접속
ssh-general: _up
    docker compose exec -it access ssh-to.sh general

# GPU 서버로 업로드 (원격 생략 시 ~/).  예) just upload-gpu /work/transfer/data.zip
upload-gpu file dest="": _up
    docker compose exec -it access upload.sh gpu "{{file}}" {{dest}}

# 일반 서버로 업로드 (원격 생략 시 ~/)
upload-general file dest="": _up
    docker compose exec -it access upload.sh general "{{file}}" {{dest}}

# GPU 서버에서 다운로드 (로컬 생략 시 ./transfer).  예) just download-gpu ~/result.zip
download-gpu remote dest="": _up
    docker compose exec -it access download.sh gpu "{{remote}}" {{dest}}

# 일반 서버에서 다운로드 (로컬 생략 시 ./transfer)
download-general remote dest="": _up
    docker compose exec -it access download.sh general "{{remote}}" {{dest}}

# 종료 (컨테이너 제거 = VPN 끊김). 저장된 프로필은 유지되어 다음 접속이 빨라짐.
shutdown:
    docker compose down

# 종료 + 저장된 인증 정보(프로필 볼륨) 삭제 → 완전 초기화.
remove:
    docker compose down --volumes
    @echo ">> 저장된 VPN 프로필을 삭제했습니다."
    @echo ">> (직접 둔 ./transfer/naver-vpn.ovpn 가 있다면 필요 시 수동 삭제하세요.)"

# 경로를 직접 줄 수도 있음:  just get-ovpn ~/Downloads/vpn2051.ovpn
# (최초 1회) 공식 앱이 저장한 .ovpn 을 transfer/ 로 추출 (호스트 실행, 컨테이너 불필요).
get-ovpn *args:
    bash tools/extract-ovpn.sh {{args}}

# ── 이하 내부/디버깅용 (평소엔 쓸 일 없음) ───────────────────────

# 컨테이너가 떠 있도록 보장 (다른 명령들이 의존).
[private]
_up:
    @test -f .env || { echo ".env 가 없습니다. cp .env.example .env 후 값을 채우세요."; exit 1; }
    @touch known_hosts
    @docker compose up -d --build >/dev/null

[private]
check target="": _up
    docker compose exec -it access check.sh {{target}}

[private]
shell: _up
    docker compose exec -it access bash

[private]
logs:
    docker compose logs -f access

[private]
vpn: _up
    docker compose exec -it access vpn.sh

[private]
vpn-stop:
    docker compose exec access vpn-stop.sh
