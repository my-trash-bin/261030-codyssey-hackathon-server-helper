#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
NCP 공공존 SSL-VPN 프로필(.ovpn) 받기 — 공식 Agent와 동일한 2단계 API 흐름.

보통은 이 스크립트가 필요 없습니다. 해커톤 도구가 접속 시(`just ssh-gpu`) 자동으로
같은 흐름을 수행하기 때문입니다. 이 스크립트는 프로필만 미리 받아두고 싶을 때 씁니다.

흐름 (공식 ncurion-sa-client 앱과 동일):
  ① POST {domain}:8443/api/v3/authstate  (type:"profile")  → state + OTP(SMS/메일) 발송
  ② POST {domain}:8443/api/v3/profile    (state + OTP)      → profile_name + profile_body(.ovpn)

- 비밀번호는 .env 없이 직접 입력(화면에 표시 안 됨). 추가 설치 불필요(표준 라이브러리).
- 받은 프로필은 transfer/naver-vpn.ovpn (없으면 현재 폴더)로 저장.

사용:
    python3 tools/fetch-ovpn.py
    OUT=~/naver-vpn.ovpn python3 tools/fetch-ovpn.py
    INSECURE=1 python3 tools/fetch-ovpn.py      # 인증서 검증 오류 시 (공식 앱도 검증 끔)
"""
import os
import sys
import ssl
import json
import base64
import getpass
import platform
import urllib.request
import urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SERVER = os.environ.get("VPN_SERVER", "sslvpn-kr-vpc-02.gov-ncloud.com")
PORT = os.environ.get("VPN_PORT", "8443")
BASE = f"https://{SERVER}:{PORT}"
CVER = os.environ.get("VPN_CLIENT_VERSION", "1.1.4")
OS_NAME = platform.system().lower() or "linux"       # 'darwin' / 'linux'
OS_VER = platform.release() or "unknown"


def default_out():
    if os.environ.get("OUT"):
        return os.path.expanduser(os.environ["OUT"])
    tdir = os.path.join(ROOT, "transfer")
    if os.path.isdir(tdir):
        return os.path.join(tdir, "naver-vpn.ovpn")
    return os.path.join(os.getcwd(), "naver-vpn.ovpn")


OUT = default_out()


def ssl_context():
    ctx = ssl.create_default_context()
    if os.environ.get("INSECURE") == "1":
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    return ctx


def api(path, payload):
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        BASE + path, data=data, method="POST",
        headers={"Content-Type": "application/json", "Api-Version": "1"},
    )
    try:
        with urllib.request.urlopen(req, timeout=20, context=ssl_context()) as r:
            raw = r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
    try:
        return json.loads(raw)
    except Exception:  # noqa: BLE001
        print("   (JSON 파싱 실패) 응답:", raw[:400])
        return None


def save_profile(b64, name):
    out_dir = os.path.dirname(OUT)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    try:
        blob = base64.b64decode(b64)
    except Exception:  # noqa: BLE001
        blob = base64.b64decode(b64 + "=" * (-len(b64) % 4))
    with open(OUT, "wb") as f:
        f.write(blob)
    text = blob.decode("utf-8", "replace")
    print(f"\n✅ 프로필 저장 완료: {OUT}")
    print(f"   프로필명 : {name}   (.env 의 VPN_OVPN_NAME 참고용)")
    for line in text.splitlines():
        if line.strip().lower().startswith(("remote ", "port ", "proto ")):
            print(f"   {line.strip()}")


def main():
    print(f"게이트웨이 : {BASE}")
    print(f"저장 위치  : {OUT}")
    print()
    user_id = input("VPN ID: ").strip()
    passwd = getpass.getpass("VPN 비밀번호(화면에 표시되지 않음): ")
    if not user_id or not passwd:
        print("ID/PW 가 비어 있습니다.", file=sys.stderr)
        return 1

    # ① authstate (type:profile) → state + OTP 발송
    print("\n>> 1차 인증 중 (ID/PW)...")
    r1 = api("/api/v3/authstate", {
        "user_id": user_id, "passwd": passwd, "type": "profile",
        "client_version": CVER, "os_name": OS_NAME, "os_version": OS_VER,
    })
    if not r1:
        return 1
    if str(r1.get("success", "")).lower() != "true":
        print(">> 1차 인증 실패:", r1.get("err_msg", "(ID/PW 확인)"))
        return 1
    state = r1.get("state") or ""
    pbody = r1.get("profile_body") or ""

    otp = ""
    if state:
        print(">> 1차 인증 성공. 이메일/SMS로 받은 OTP 코드를 입력하세요.")
        otp = input("OTP: ").strip()
        if not otp:
            print(">> OTP가 입력되지 않았습니다.", file=sys.stderr)
            return 1
    else:
        print(">> 1차 인증 성공 (OTP 불필요).")

    # ② 프로필 확보: authstate 직수신 → 아니면 /api/v3/profile 다운로드
    if pbody:
        save_profile(pbody, r1.get("profile_name") or "profile.ovpn")
    else:
        print("\n>> 프로필 다운로드 중 (/api/v3/profile)...")
        r2 = api("/api/v3/profile", {
            "user_id": user_id, "auth_type": 1, "otp_passwd": otp, "state": state,
            "client_version": CVER, "os_name": OS_NAME, "os_version": OS_VER,
        })
        if not r2:
            return 1
        if str(r2.get("success", "")).lower() != "true":
            print(">> 프로필 다운로드 실패:", r2.get("err_msg", "(알 수 없음)"))
            print(">> (OTP가 틀렸거나 만료됐을 수 있습니다. 다시 실행하세요.)")
            return 1
        pb = r2.get("profile_body") or ""
        if not pb:
            print(">> 응답에 프로필이 없습니다.")
            return 1
        save_profile(pb, r2.get("profile_name") or "profile.ovpn")

    print("\n🎉 완료. 'just ssh-gpu' (또는 ./hak ssh-gpu) 로 접속하세요.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n중단됨.")
        sys.exit(130)
