# 2026 해커톤 서버 접속 토이킷
# 사용 전: cp .env.example .env  후 값 입력
.DEFAULT_GOAL := help
DC := docker compose
EXEC := $(DC) exec access
EXECIT := $(DC) exec -it access

.PHONY: help build up down logs shell vpn check \
        ssh-general ssh-gpu upload-general upload-gpu download-general download-gpu

help: ## 명령 목록 보기
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	 | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

build: ## 이미지 빌드
	$(DC) build

up: ## 접속 컨테이너 시작 (백그라운드 유지)
	@test -f .env || { echo ".env 가 없습니다. cp .env.example .env 후 값을 채우세요."; exit 1; }
	@touch known_hosts
	$(DC) up -d --build

down: ## 컨테이너 중지/제거
	$(DC) down

logs: ## 컨테이너 로그
	$(DC) logs -f access

shell: ## 컨테이너 안으로 셸 진입
	$(EXECIT) bash

vpn: ## SSL-VPN 연결 (OTP 입력, 이 터미널 유지)
	$(EXECIT) vpn.sh

check: ## VPN 연결 후 서버 SSH 포트 도달 점검
	$(EXEC) check.sh

ssh-general: ## 일반 서버 터미널 접속
	$(EXECIT) ssh-to.sh general

ssh-gpu: ## GPU 서버 터미널 접속
	$(EXECIT) ssh-to.sh gpu

# 예) make upload-gpu FILE=/work/transfer/data.zip DEST=~/
upload-general: ## 일반 서버로 업로드 (FILE=, DEST= 선택)
	$(EXEC) upload.sh general "$(FILE)" $(DEST)

upload-gpu: ## GPU 서버로 업로드 (FILE=, DEST= 선택)
	$(EXEC) upload.sh gpu "$(FILE)" $(DEST)

# 예) make download-gpu REMOTE=~/result.zip DEST=/work/transfer/
download-general: ## 일반 서버에서 다운로드 (REMOTE=, DEST= 선택)
	$(EXEC) download.sh general "$(REMOTE)" $(DEST)

download-gpu: ## GPU 서버에서 다운로드 (REMOTE=, DEST= 선택)
	$(EXEC) download.sh gpu "$(REMOTE)" $(DEST)
