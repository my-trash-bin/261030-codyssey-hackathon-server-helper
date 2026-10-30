#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
[대안] 공식 앱 없이 API(authstate)로 .ovpn 프로필 받아보기.

주의: 테넌트에 "서버 선택 메뉴"가 있으면 이 방식은 실패할 수 있습니다
(그 경우 tools/extract-ovpn.sh 로 공식 클라이언트 프로필을 추출하세요).
추가 설치 불필요(파이썬 표준 라이브러리만).

사용:
    python3 tools/fetch-ovpn.py
    VPN_OVPN_NAME=vpn2051.ovpn python3 tools/fetch-ovpn.py   # 번호를 알 때
"""
import os
import sys
import ssl
import json
import base64
import getpass
import urllib.request
import urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SERVER = os.environ.get("VPN_SERVER", "sslvpn-kr-vpc-02.gov-ncloud.com")
PORT = os.environ.get("VPN_PORT", "8443")
API = f"https://{SERVER}:{PORT}/api/v3/authstate"
MAC = os.environ.get("VPN_MAC", "02-00-00-00-00-01")


def default_out():
    if os.environ.get("OUT"):
        return os.path.expanduser(os.environ["OUT"])
    tdir = os.path.join(ROOT, "transfer")
    if os.path.isdir(tdir):
        return os.path.join(tdir, "naver-vpn.ovpn")
    return os.path.join(ROOT, "naver-vpn.ovpn")


OUT = default_out()


def ssl_context():
    if os.environ.get("INSECURE") == "1":
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        return ctx
    return ssl.create_default_context()


def post_authstate(user_id, passwd, ovpn_name):
    payload = {
        "user_id": user_id,
        "passwd": passwd,
        "type": "connect",
        "client_version": "1.1.3",
        "os_name": "darwin",
        "os_version": "macos",
        "mac": [MAC],
    }
    if ovpn_name is not None:
        payload["ovpn_file_name"] = ovpn_name
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        API, data=data, method="POST",
        headers={"Content-Type": "application/json", "Api-Version": "1"},
    )
    try:
        with urllib.request.urlopen(req, timeout=25, context=ssl_context()) as r:
            raw = r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
    except Exception as e:  # noqa: BLE001
        print(f"   (요청 실패: {e})")
        return None, None
    try:
        return json.loads(raw), raw
    except Exception:  # noqa: BLE001
        return None, raw


def save_profile(b64):
    out_dir = os.path.dirname(OUT)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    try:
        data = base64.b64decode(b64)
    except Exception:  # noqa: BLE001
        data = base64.b64decode(b64 + "=" * (-len(b64) % 4))
    with open(OUT, "wb") as f:
        f.write(data)
    return data.decode("utf-8", "replace")


def attempt(label, user_id, passwd, ovpn_name):
    print(f"── 시도: {label}")
    resp, raw = post_authstate(user_id, passwd, ovpn_name)
    if resp is None:
        if raw:
            print("   (JSON 파싱 실패) 응답:", raw[:400])
        return 1, raw
    success = str(resp.get("success", "")).lower()
    err_msg = resp.get("err_msg", "") or ""
    state = resp.get("state", "") or ""
    plen = resp.get("profile_len", 0)
    pbody = resp.get("profile_body") or ""
    print(f"   success={success}  state={state}  profile_len={plen}")
    if err_msg:
        print(f"   err_msg={err_msg}")
    if success != "true":
        print("   → 1차 인증 실패. (ID/PW 확인)")
        return 2, raw
    if pbody:
        text = save_profile(pbody)
        print(f"   ✅ 프로필 저장 완료: {OUT}")
        for line in text.splitlines():
            if line.strip().lower().startswith(("remote ", "port ", "proto ")):
                print(f"        {line.strip()}")
        return 0, raw
    print("   → 1차 인증은 성공했지만 이 이름으로는 프로필을 주지 않음.")
    return 1, raw


def main():
    print(f"대상 게이트웨이 : {API}")
    print(f"저장 위치       : {OUT}")
    print()
    user_id = input("VPN ID: ").strip()
    passwd = getpass.getpass("VPN 비밀번호(화면에 표시되지 않음): ")
    if not user_id or not passwd:
        print("ID/PW 가 비어 있습니다.", file=sys.stderr)
        return 1
    print()
    print(">> 1차 인증이 성공할 때마다 SMS/이메일 OTP 가 발송됩니다. (프로필만 받으면 무시 가능)")
    print()

    candidates = []
    env_name = os.environ.get("VPN_OVPN_NAME")
    if env_name:
        candidates.append((f"지정한 이름 ({env_name})", env_name))
    candidates.append(("이름 필드 생략(계정 기본 프로필 기대)", None))
    candidates.append(("빈 이름", ""))
    candidates.append(("과거 기본값 vpn2033.ovpn", "vpn2033.ovpn"))

    last_raw = ""
    for label, name in candidates:
        rc, last_raw = attempt(label, user_id, passwd, name)
        if rc == 0:
            print()
            print("🎉 완료. 'just ssh-gpu' (또는 ./hak ssh-gpu) 로 접속하세요.")
            return 0
        if rc == 2:
            break
        print()

    print()
    print("⚠️  프로필을 받지 못했습니다. (메뉴형 테넌트일 수 있음)")
    print("    → tools/extract-ovpn.sh 로 공식 클라이언트 프로필을 추출하세요.")
    print()
    print("서버의 마지막 응답 전문:")
    try:
        print(json.dumps(json.loads(last_raw), ensure_ascii=False, indent=2))
    except Exception:  # noqa: BLE001
        print(last_raw)
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n중단됨.")
        sys.exit(130)
