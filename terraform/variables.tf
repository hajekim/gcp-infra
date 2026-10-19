variable "project_id" {
  description = "실습을 진행할 Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "기본 배포 리전"
  type        = string
  default     = "asia-northeast3"
}

variable "zones" {
  description = "Regional MIG 멀티존 분산 대상 존 목록"
  type        = list(string)
  default     = ["asia-northeast3-a", "asia-northeast3-b", "asia-northeast3-c"]
}

variable "prefix" {
  description = "리소스 이름 접두사"
  type        = string
  default     = "gce-ws"
}

variable "machine_type" {
  description = "GCE 머신 타입 (gVNIC 지원 시리즈)"
  type        = string
  default     = "e2-standard-2"
}

variable "target_size" {
  description = "Regional MIG 목표 인스턴스 수"
  type        = number
  default     = 3
}

variable "app_version" {
  description = "애플리케이션 배포 버전 식별자 (v1 -> v2 롤링 업데이트 실습용)"
  type        = string
  default     = "v1"
}

variable "keepalive_timeout_sec" {
  description = "백엔드 서버 HTTP Keep-Alive 타임아웃(초). 620초 권장, 502 에러 재현 시 2초로 변경"
  type        = number
  default     = 620
}
