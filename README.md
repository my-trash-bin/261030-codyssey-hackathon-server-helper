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
- **`just` 없이**: 동일 기능의 셸 래퍼 `./hak <명령>` (예: `./hak ssh-gpu`, `./hak shutdown`)

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

> 프로필(.ovpn)은 접속할 때 **자동으로 받아옵니다.** 미리 준비할 것은 위 `.env` 뿐입니다.
> (공식 앱 설치·프로필 번호 입력 모두 불필요 — 아래 "VPN 클라이언트에 대한 참고" 참조.)

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

`just` 와 `./hak` 모두 동일합니다. 알아야 할 명령은 이게 전부입니다.

```bash
just ssh-gpu                         # GPU 서버 접속   / just ssh-general
just upload-gpu   <로컬경로> [원격경로]    # 업로드
just download-gpu <원격경로> [로컬경로]    # 다운로드
just shutdown                        # 종료 (저장된 프로필은 유지)
just remove                          # 종료 + 저장된 인증 정보까지 삭제 (완전 초기화)
```

컨테이너 시작과 VPN 연결은 전부 자동입니다.

**인증 정보 유지에 대해:**
- **컨테이너를 켜 둔 동안**에는 VPN 세션이 유지되어 `ssh-*`/`upload`/`download` 를
  **OTP 재입력 없이** 바로 쓸 수 있습니다.
- `shutdown` 은 컨테이너만 내리고 **받아둔 VPN 프로필(.ovpn/인증서)은 저장해 둡니다.**
  다음에 다시 켜면 프로필을 재사용하므로 더 빠릅니다.
- 단, **OTP(1회용 코드)는 보관할 수 없습니다.** 컨테이너를 완전히 내린 뒤 다시 접속하면
  OTP는 한 번 더 입력해야 합니다(VPN 2차 인증 특성).
- `remove` 는 저장된 프로필까지 지워 **완전 초기화**합니다. 문제가 꼬였을 때 쓰세요.

> 참고: `just get-ovpn` 은 자동 수신이 안 될 때 공식 앱의 `.ovpn` 을 추출하는 **대안**입니다(평소엔 불필요).
> 그 밖의 디버깅용 숨은 명령(`check`, `shell`, `logs`, `vpn-stop`)도 평소엔 필요 없습니다.

## VPN 클라이언트에 대한 참고

NCP 공공존 SSL VPN은 **OpenVPN 기반**입니다. 공식 Agent(Windows/macOS)는 openvpn을
품은 앱일 뿐이라, 리눅스에서는 컨테이너 안의 `openvpn` 으로 그대로 붙습니다
(별도 VM·공식 Agent 불필요).

이 도구는 공식 Agent(`ncurion-sa-client`)와 **똑같은 2단계 v3 API** 를 수행하므로,
프로필 번호를 몰라도 되고 공식 앱도 필요 없습니다. 연결 흐름(자동):
1. `.env` 의 ID/PW 로 `POST /api/v3/authstate` (`type:"profile"`) → `state` 수신 +
   **SMS/이메일로 OTP 발송**
2. 터미널에 **OTP 한 번 입력**
3. `POST /api/v3/profile` 에 `state`+OTP 전달 → **올바른 `.ovpn` 프로필 자동 수신**
4. `openvpn` 이 같은 아이디+OTP 로 터널 연결 (포트 12000~13000)

즉 사용자는 **OTP만 한 번** 입력하면 끝입니다. 비밀번호는 `.env` 에서 자동 사용됩니다.
(프로필만 미리 받아두고 싶으면 `python3 tools/fetch-ovpn.py` 로 동일 흐름을 돌릴 수 있습니다.)

한 번 받은 `.ovpn` 은 볼륨에 저장돼 다음 접속에 **재사용**됩니다(3번 다운로드를 건너뜀).
다만 OTP(4번의 터널 인증)는 `authstate` 때만 발송되므로 **새 연결마다 한 번은 필요**합니다
— OTP 없이 바로 쓰려면 컨테이너를 켜 두세요(tun 이 살아 있으면 재인증 없이 즉시 사용).
프로필을 강제로 새로 받으려면 `.env` 에 `VPN_REFRESH=1`, 완전 초기화는 `just remove`.

연결 문제 시:
- `1차 인증 실패` → `.env` 의 `VPN_ID`/`VPN_PW` 확인 (포털 응답의 `err_msg` 를 그대로 보여줍니다).
- `프로필 다운로드 실패` → OTP 가 틀렸거나 만료됨. 다시 접속을 시도하세요(새 OTP 발송).
- (대안) 자동 수신이 끝내 안 되면, 공식 앱으로 한 번 로그인한 뒤 `just get-ovpn` 으로
  프로필을 추출해 `transfer/naver-vpn.ovpn` 에 두면 그 파일을 그대로 씁니다.
- 그 외 점검 순서: VPN 연결 → 사설 IP → SSH 포트 → 계정 `ncloud`.

## 서버 반납 일정

운영진 공지 기준 삭제 일정 확인 — 삭제 후 복구 불가하니 사전 백업 필수.

## 라이선스 (꼭 읽어주세요, 아주 간단함)

자유롭게 쓰고 고치고 나눠도 됩니다. **딱 한 가지 조건**만 지켜주세요:

> **2026 코디세이 해커톤에서 이 툴을 썼다면, 발표 자료에 "'지피에게 물어보죠' 팀의
> 연결 툴을 사용했다" 는 한 줄만 넣어주세요.**

예) `서버 연결에 '지피에게 물어보죠' 팀의 연결 툴을 사용했습니다.`

그게 전부입니다. 전문은 [`LICENSE`](./LICENSE) 참고.

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
