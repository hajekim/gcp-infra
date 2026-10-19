#!/usr/bin/env python3
"""
Keep-Alive 타임아웃 미스매치(백엔드 2초 vs LB 600초) 상황에서
유휴 소켓 만료 타이밍에 맞춰 POST 요청을 전송해 502 Bad Gateway를 재현하는 스크립트입니다.
"""

import sys
import time
import urllib.request
import urllib.error

def trigger_502(vip: str, wait_sec: float = 1.98):
    url = f"http://{vip}/api/transaction"
    print(f"[*] Target URL: {url}")
    print(f"[*] Reproducing Keep-Alive race condition around {wait_sec}s idle window...")

    for attempt in range(1, 31):
        try:
            req1 = urllib.request.Request(url, data=b'{"step":1}', method="POST")
            with urllib.request.urlopen(req1, timeout=5) as r1:
                _ = r1.read()

            # 백엔드 Keep-Alive(2초)가 닫히기 직전/직후 경계 시간 대기
            time.sleep(wait_sec)

            req2 = urllib.request.Request(url, data=b'{"step":2}', method="POST")
            with urllib.request.urlopen(req2, timeout=5) as r2:
                print(f"[{attempt:02d}] HTTP {r2.status} (Normal response)")
        except urllib.error.HTTPError as e:
            print(f"[{attempt:02d}] HTTP {e.code} {e.reason} <-- 502 Bad Gateway Reproduced!")
        except Exception as ex:
            print(f"[{attempt:02d}] Connection Error: {ex}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <ALB_VIP> [idle_wait_sec]")
        sys.exit(1)
    vip_arg = sys.argv[1]
    wait_arg = float(sys.argv[2]) if len(sys.argv) > 2 else 1.98
    trigger_502(vip_arg, wait_arg)
