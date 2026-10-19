# Google Compute Engine 아키텍처 심화 및 실전 구축·운영 핸즈온

웹사이트 주소: [https://gcp.geap.dev](https://gcp.geap.dev)

엔터프라이즈 인프라 운영팀 및 네트워크 운영팀을 위해 Google Compute Engine, Managed Instance Group, Cloud Load Balancing의 내부 동작 원리와 실전 구축, 무중단 배포 및 트러블슈팅을 다루는 기술 포털 및 실습 저장소입니다.

## 커리큘럼 구성

| 세션 | 세션명 | 핵심 내용 |
| :--- | :--- | :--- |
| **Session 1** | GCE 코어 아키텍처 및 엔터프라이즈 구축 가이드 | 머신 시리즈 선택 기준, gVNIC / Tier 1 고대역폭 네트워킹, Live Migration, Persistent Disk vs Hyperdisk 동적 프로비저닝, Golden Image 파이프라인 vs Startup/Shutdown 스크립트, Global VPC, Service Account 및 IAM Tags 기반 방화벽, Metadata Server 보안, OS Login + IAP Tunneling |
| **Session 2** | Instance Group 구조 및 라이프사이클 운영 | UMIG vs MIG 아키텍처, Regional MIG 멀티존 분산 알고리즘, Rolling Update 및 Canary 배포, maxSurge / maxUnavailable / minReadySec 설계, 다중 지표 Autoscaling 및 Scale-in Control, Autohealing Health Check와 Load Balancer Health Check 분리, Stateful MIG 운영 패턴 |
| **Session 3** | Cloud Load Balancing 아키텍처 및 트래픽 제어 | GFE 및 Andromeda SDN 기반 분산 아키텍처, Maglev 및 Envoy 동작 원리와 즉시 확장 특성, Proxy LB vs Passthrough LB 패킷 흐름 및 클라이언트 Source IP 보존, L7 ALB & L4 NLB 컴포넌트 상세, Balancing Mode 설계, Connection Draining, Keep-alive 타임아웃 튜닝 |
| **Session 4** | Day-2 운영, 트러블슈팅 가이드 및 아키텍처 Q&A | Ops Agent 메트릭/로그 수집, LB 로그 분석을 통한 네트워크/백엔드 병목 구간 특정, Serial Console 분석, Connectivity Tests 기반 방화벽/라우팅 검증, Terraform으로 MIG/Instance Template 운영 시 무중단 교체 패턴 |

## 디렉토리 구조

- `index.html`: 아키텍처 심화 가이드 및 인터랙티브 핸즈온 실습 포털 (`https://gcp.geap.dev`)
- `slides.html`: 3시간(4개 세션) 강의용 웹 기반 프레젠테이션 슬라이드 데크 (98장, 발표자 노트 및 폰트 확대/축소 지원, `https://gcp.geap.dev/slides.html`)
- `proposal.html`: 일정 옵션별 상세 교육 아젠다 (`https://gcp.geap.dev/proposal.html`)
- `terraform/`: 베이스라인 인프라(VPC, Cloud NAT, Private MIG, L7 ALB) 즉시 프로비저닝 및 무중단 템플릿 교체 검증용 Terraform 코드
- `scripts/`: 502 Bad Gateway 장애 주입 및 무중단 롤링 업데이트 실시간 모니터링 스크립트
