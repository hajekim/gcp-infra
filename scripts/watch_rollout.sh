#!/usr/bin/env bash
# MIG 무중단 배포 및 502 Bad Gateway 장애 주입 시 실시간 응답 상태를 모니터링합니다.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <ALB_VIP>"
  exit 1
fi

ALB_VIP="$1"
echo "Monitoring http://${ALB_VIP}/ (Interval: 0.5s) ..."
echo "--------------------------------------------------------------------------------"

while true; do
  TS=$(date +"%H:%M:%S")
  RESP=$(curl -s -w "\n%{http_code} %{time_total}" "http://${ALB_VIP}/" -X POST -d '{"probe":"keepalive"}' || echo -e "\n000 0.000")
  BODY=$(echo "$RESP" | head -n 1)
  META=$(echo "$RESP" | tail -n 1)
  CODE=$(echo "$META" | awk '{print $1}')
  LAT=$(echo "$META" | awk '{print $2}')

  if [[ "$CODE" == "200" ]]; then
    VER=$(echo "$BODY" | grep -o '"version": *"[^"]*"' | cut -d'"' -f4 || echo "-")
    INST=$(echo "$BODY" | grep -o '"instance": *"[^"]*"' | cut -d'"' -f4 || echo "-")
    ZONE=$(echo "$BODY" | grep -o '"zone": *"[^"]*"' | cut -d'"' -f4 || echo "-")
    KA=$(echo "$BODY" | grep -o '"keepalive_timeout_sec": *[0-9]*' | awk -F: '{print $2}' | tr -d ' ' || echo "-")
    printf "[%s] HTTP %s (%ss) | ver=%-4s | vm=%-20s | zone=%-18s | keepalive=%ss\n" "$TS" "$CODE" "$LAT" "$VER" "$INST" "$ZONE" "$KA"
  else
    printf "[%s] HTTP %s (%ss) | ERROR_DETECTED (Check Cloud Logging statusDetails)\n" "$TS" "$CODE" "$LAT"
  fi
  sleep 0.5
done
