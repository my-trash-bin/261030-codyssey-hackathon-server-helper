# 2026 해커톤 서버 접속 토이킷

공공존 VPC GPU 서버 접속 절차(**SSL-VPN 연결 → SSH 터미널 → 파일 업로드/다운로드**)를
Docker 하나로 처리하는 도구 모음입니다. 일반 서버·GPU 서버 2대를 모두 지원합니다.

## 구성 흐름

```
내 PC ──(SSL-VPN, OTP)──> 공공존 VPC ──(SSH/SFTP, 사설 IP)──> 일반/GPU 서버
        [ hackathon-access 컨테이너가 VPN을 쥐고, 그 안에서 ssh/scp 실행 ]
```

VPN 연결을 컨테이너가 보유하고, SSH·전송 명령은 같은 컨테이너에서(`docker compose exec`)
실행되므로 VPN 라우팅을 그대로 탑니다.

## 1. 준비

```bash
cp .env.example .env     # 값 입력 (아래 항목 참고)
make up                  # 이미지 빌드 + 접속 컨테이너 시작
```

`.env` 에 채울 값:

| 구분 | 키 | 설명 |
|------|----|------|
| VPN | `VPN_SERVER`, `VPN_PORT` | 게이트웨이 (기본: `sslvpn-kr-vpc-02.gov-ncloud.com:8443`) |
| VPN | `VPN_ID`, `VPN_PW` | VPN 접속 ID/PW (OTP는 연결 시 직접 입력) |
| 일반 서버 | `GENERAL_HOSTNAME`, `GENERAL_IP`, `GENERAL_USER`, `GENERAL_PASSWORD`, `GENERAL_SSH_PORT` | `USER` 기본 `ncloud`, 포트 기본 `22` |
| GPU 서버 | `GPU_HOSTNAME`, `GPU_IP`, `GPU_USER`, `GPU_PASSWORD`, `GPU_SSH_PORT` | 동일 |

> `.env` 는 `.gitignore` 로 커밋되지 않습니다. 비밀번호·OTP를 공유하지 마세요.

## 2. VPN 연결

```bash
make vpn     # OTP 코드를 물어보면 이메일/SMS로 받은 코드 입력, 이 터미널은 켜 둔 채 유지
```

연결을 유지한 상태에서 **다른 터미널**을 열어 아래 명령을 사용합니다.
도달 확인:

```bash
make check   # 각 서버 SSH 포트가 열려 있는지 점검
```

## 3. 터미널 접속

```bash
make ssh-gpu        # GPU 서버 셸
make ssh-general    # 일반 서버 셸
```

GPU 확인: 접속 후 `nvidia-smi`,
`python3 -c "import torch; print(torch.cuda.is_available())"`.

## 4. 파일 업로드 / 다운로드

호스트의 `./transfer` 폴더가 컨테이너의 `/work/transfer` 로 공유됩니다.
업로드할 파일은 여기에 두고, 내려받은 파일도 여기로 모입니다.

```bash
# 업로드 (예: transfer/data.zip → GPU 서버 홈)
make upload-gpu FILE=/work/transfer/data.zip

# 원격 경로 지정
make upload-gpu FILE=/work/transfer/data.zip DEST=~/datasets/

# 다운로드 (예: GPU 서버의 결과물 → transfer/)
make download-gpu REMOTE=~/result.zip
```

`rsync` 기반이라 진행률 표시·재개·대용량 전송에 유리합니다.

## 명령 요약

```bash
make            # 전체 명령 목록
make up         # 컨테이너 시작
make vpn        # VPN 연결 (OTP)
make check      # 포트 도달 점검
make ssh-gpu    # / ssh-general
make upload-gpu FILE=...    DEST=...
make download-gpu REMOTE=... DEST=...
make shell      # 컨테이너 내부 셸
make down       # 정리
```

## VPN 클라이언트에 대한 참고 (중요)

이 토이킷의 VPN 연결은 `openfortivpn`(Fortinet 계열 SSL-VPN CLI)을 사용합니다.
공공존 게이트웨이가 Fortinet 호환이 **아닐 경우** `make vpn` 이 실패할 수 있습니다.
공공존 VPC는 Windows/macOS용 공식 *NAVER Cloud SSL VPN Agent* 만 제공하며
Linux CLI는 공식 지원되지 않습니다.

- 공식 Agent가 동작하는 OS를 쓸 수 있다면, 호스트에서 먼저 VPN을 연결한 뒤
  `docker-compose.yml` 에 `network_mode: host` 를 더해 쓰는 방법이 가장 확실합니다.
- 그 경우에도 `ssh-to.sh` / `upload.sh` / `download.sh` 는 그대로 동작합니다.

연결 문제 시 점검 순서(VPN 연결 → 사설 IP → SSH 포트 → 계정 `ncloud`)를 따르세요.

## 서버 반납 일정

운영진 공지 기준 삭제 일정 확인 — 삭제 후 복구 불가하니 사전 백업 필수.
