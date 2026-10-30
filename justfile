# 2026 해커톤 서버 접속 토이킷 (just)
# just 가 없으면 동일 기능의 ./hak 셸 스크립트를 쓰세요.
# 사용 전: cp .env.example .env  후 값 입력

_default:
    @just --list

# 이미지 빌드 + 접속 컨테이너 시작 (백그라운드 유지)
up:
    @test -f .env || { echo ".env 가 없습니다. cp .env.example .env 후 값을 채우세요."; exit 1; }
    @touch known_hosts
    docker compose up -d --build

# 컨테이너 중지/제거
down:
    docker compose down

# 컨테이너 로그
logs:
    docker compose logs -f access

# 컨테이너 안으로 셸 진입
shell:
    docker compose exec -it access bash

# SSL-VPN 연결 (OTP 입력, 이 터미널 유지)
vpn:
    docker compose exec -it access vpn.sh

# VPN 연결 후 서버 SSH 포트 도달 점검 (target: general|gpu, 생략 시 둘 다)
check target="":
    docker compose exec access check.sh {{target}}

# 일반 서버 터미널 접속
ssh-general:
    docker compose exec -it access ssh-to.sh general

# GPU 서버 터미널 접속
ssh-gpu:
    docker compose exec -it access ssh-to.sh gpu

# 일반 서버로 업로드 (dest 생략 시 ~/)
upload-general file dest="":
    docker compose exec access upload.sh general "{{file}}" {{dest}}

# GPU 서버로 업로드 (dest 생략 시 ~/)
upload-gpu file dest="":
    docker compose exec access upload.sh gpu "{{file}}" {{dest}}

# 일반 서버에서 다운로드 (dest 생략 시 /work/transfer/)
download-general remote dest="":
    docker compose exec access download.sh general "{{remote}}" {{dest}}

# GPU 서버에서 다운로드 (dest 생략 시 /work/transfer/)
download-gpu remote dest="":
    docker compose exec access download.sh gpu "{{remote}}" {{dest}}
