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

## 요구 사항

**Docker(+ compose plugin)만 있으면 됩니다.** VPN 클라이언트·ssh·rsync 등은 모두 이미지 안에 포함됩니다.
VPN 사용 시 호스트에 `/dev/net/tun` 이 필요합니다(리눅스 기본 존재).

명령 실행은 두 가지 중 편한 쪽을 쓰세요.
- **`just` 사용** (권장): `mise` 로 설치 후 `just <명령>`
  ```bash
  mise install          # .mise.toml 기준 just 설치
  just                  # 명령 목록
  just up
  ```
  mise 가 셸에 활성화돼 있지 않으면 `mise exec -- just <명령>` 형태로 쓰세요.
- **`just` 없이**: 동일 기능의 셸 래퍼 `./hak <명령>` (예: `./hak ssh-gpu`, `./hak down`)

아래 예시는 `just` 기준이며, 모든 명령은 `./hak` 로도 동일하게 동작합니다.

## 1. 준비 (한 번만)

```bash
cp .env.example .env     # 값 입력 (아래 항목 참고)
```

`.env` 에 채울 값:

| 구분 | 키 | 설명 |
|------|----|------|
| VPN | `VPN_SERVER`, `VPN_PORT` | 게이트웨이 (기본: `sslvpn-kr-vpc-02.gov-ncloud.com:8443`) |
| VPN | `VPN_ID`, `VPN_PW` | VPN 접속 ID/PW (OTP는 접속 시 자동으로 물어봄) |
| 일반 서버 | `GENERAL_HOSTNAME`, `GENERAL_IP`, `GENERAL_USER`, `GENERAL_PASSWORD`, `GENERAL_SSH_PORT` | `USER` 기본 `ncloud`, 포트 기본 `22` |
| GPU 서버 | `GPU_HOSTNAME`, `GPU_IP`, `GPU_USER`, `GPU_PASSWORD`, `GPU_SSH_PORT` | 동일 |

> `.env` 는 `.gitignore` 로 커밋되지 않습니다. 비밀번호·OTP를 공유하지 마세요.

## 2. 접속 (이게 전부)

```bash
just ssh-gpu        # GPU 서버 셸   (또는 ./hak ssh-gpu)
just ssh-general    # 일반 서버 셸
```

이 한 줄이 **컨테이너 시작 → VPN 연결 → SSH 접속**을 알아서 처리합니다.
- VPN이 안 떠 있으면 자동으로 연결하며, **이때 OTP 코드만 한 번 입력**하면 됩니다.
- 한 번 연결되면 컨테이너가 연결을 유지하므로, 이후 `just ssh-*` 는 바로 붙습니다.

GPU 확인: 접속 후 `nvidia-smi`,
`python3 -c "import torch; print(torch.cuda.is_available())"`.

도달 점검이 필요하면:

```bash
just check          # 각 서버 SSH 포트 도달 확인 (필요 시 VPN 자동 연결)
```

## 4. 파일 업로드 / 다운로드

호스트의 `./transfer` 폴더가 컨테이너의 `/work/transfer` 로 공유됩니다.
업로드할 파일은 여기에 두고, 내려받은 파일도 여기로 모입니다.
인자는 위치 인자입니다: `upload-<서버> <로컬경로> [원격경로]`.

```bash
# 업로드 (예: transfer/data.zip → GPU 서버 홈)
just upload-gpu /work/transfer/data.zip

# 원격 경로 지정
just upload-gpu /work/transfer/data.zip ~/datasets/

# 다운로드 (예: GPU 서버의 결과물 → transfer/)
just download-gpu ~/result.zip
```

`rsync` 기반이라 진행률 표시·재개·대용량 전송에 유리합니다.

## 명령 요약 (이게 전부)

`just` 와 `./hak` 모두 동일합니다. 알아야 할 명령은 아래 7개뿐입니다.

```bash
just ssh-gpu                         # GPU 서버 접속   / just ssh-general
just upload-gpu   <로컬경로> [원격경로]    # 업로드
just download-gpu <원격경로> [로컬경로]    # 다운로드
just down                            # 정리 / 초기화
```

컨테이너 시작과 VPN 연결은 전부 자동입니다. 문제가 생기면 `just down` 후 다시
`just ssh-*` 하면 처음부터 재연결(OTP 재입력)됩니다.

> 참고: 디버깅용 숨은 명령(`check`, `shell`, `logs`, `vpn-stop`)도 있지만 평소엔 필요 없습니다.

## VPN 클라이언트에 대한 참고

NCP 공공존 SSL VPN은 **F5 BIG-IP Edge** 기반입니다. 공식 Agent는 Windows/macOS
전용이지만, 리눅스에서는 **`openconnect --protocol=f5`** 로 붙을 수 있어 이 토이킷은
컨테이너 안에서 openconnect로 자동 연결합니다 (별도 VM·공식 Agent 불필요).

인증 흐름: 비밀번호는 `.env` 에서 자동 입력되고, **OTP(이메일/SMS 코드)만 접속 시
한 번 터미널에서 입력**하면 됩니다.

자동 연결이 안 되면 아래로 수동 확인할 수 있습니다(비번·OTP 모두 직접 입력):

```bash
docker compose exec -it access sh -c \
  'openconnect --protocol=f5 -u "$VPN_ID" "https://$VPN_SERVER:$VPN_PORT"'
```

연결 문제 시 점검 순서(VPN 연결 → 사설 IP → SSH 포트 → 계정 `ncloud`)를 따르세요.

## 서버 반납 일정

운영진 공지 기준 삭제 일정 확인 — 삭제 후 복구 불가하니 사전 백업 필수.

## 라이선스

이 저장소는 **Codyssey Hackathon Server Helper License (Usage-Disclosure License v1.0)** 를 따릅니다.
자유롭게 사용·수정·배포할 수 있으나, **사용 시 "이 소프트웨어를 사용했다"는 사실을
공개적으로(또는 비공개 사용 시 내부 기록으로) 남겨야 합니다.** 전문은 [`LICENSE`](./LICENSE) 참고.

## 개발: 원격 저장소를 GitHub에 푸시

`gh`에 로그인된 PC에서 다음 스크립트를 실행하세요.

```bash
./push.sh
```

기본으로 `remote-sub-1:/home/mjy/tmp`의 `main` 커밋 이력을 임시 디렉터리로
가져와 이 PC의 GitHub 인증으로 이 저장소에 푸시합니다. 원격 서버에 인증 정보를
복사하지 않으며, 작업 후 임시 디렉터리는 제거합니다. 원격 서버에서 먼저 커밋해야
하며, 커밋되지 않은 변경은 포함하지 않습니다. 강제 푸시는 하지 않습니다.
스크립트는 어느 디렉터리에서든 실행할 수 있습니다.

다른 호스트·경로·대상·브랜치도 지정할 수 있습니다.

```bash
./push.sh remote-sub-1 /home/mjy/tmp https://github.com/my-trash-bin/261030-codyssey-hackathon-server-helper.git main
```
