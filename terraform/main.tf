terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# 1. Global VPC 및 Regional Subnet
resource "google_compute_network" "vpc" {
  name                    = "${var.prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
}

resource "google_compute_subnetwork" "app_subnet" {
  name                     = "${var.prefix}-app-subnet"
  ip_cidr_range            = "10.10.0.0/20"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

# Regional / Internal Envoy 기반 LB를 위한 Proxy-only Subnet
resource "google_compute_subnetwork" "proxy_subnet" {
  name          = "${var.prefix}-proxy-only-subnet"
  ip_cidr_range = "10.129.0.0/23"
  region        = var.region
  network       = google_compute_network.vpc.id
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

# 2. Cloud Router 및 Cloud NAT (동적 포트 할당 활성화로 포트 고갈 방지)
resource "google_compute_router" "router" {
  name    = "${var.prefix}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.prefix}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  enable_dynamic_port_allocation      = true
  min_ports_per_vm                    = 256
  max_ports_per_vm                    = 4096
  enable_endpoint_independent_mapping = false

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# 3. 전용 Service Account 및 방화벽 정책 (IAP Tunneling & Google Health Check)
resource "google_service_account" "app_sa" {
  account_id   = "${var.prefix}-app-sa"
  display_name = "GCE Workshop App Service Account"
}

resource "google_project_iam_member" "log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.app_sa.email}"
}

resource "google_project_iam_member" "metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.app_sa.email}"
}

# IAP TCP Forwarding (35.235.240.0/20 -> TCP 22)
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "${var.prefix}-allow-iap-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges           = ["35.235.240.0/20"]
  target_service_accounts = [google_service_account.app_sa.email]
}

# Google Front End / Health Check Probers & Proxy-only Subnet -> TCP 8080
resource "google_compute_firewall" "allow_lb_and_hc" {
  name    = "${var.prefix}-allow-lb-hc"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22",
    google_compute_subnetwork.proxy_subnet.ip_cidr_range
  ]
  target_service_accounts = [google_service_account.app_sa.email]
}

# 4. 헬스체크 이원화: LB Readiness Check vs Autohealing Liveness Check
resource "google_compute_health_check" "lb_ready_hc" {
  name                = "${var.prefix}-lb-ready-hc"
  check_interval_sec  = 5
  timeout_sec         = 3
  healthy_threshold   = 2
  unhealthy_threshold = 2

  http_health_check {
    port         = 8080
    request_path = "/healthz/ready"
  }
}

resource "google_compute_health_check" "autoheal_live_hc" {
  name                = "${var.prefix}-autoheal-live-hc"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 8080
    request_path = "/healthz/live"
  }
}

# 5. Instance Template (name_prefix + create_before_destroy 필수 패턴)
resource "google_compute_instance_template" "app_v1" {
  name_prefix  = "${var.prefix}-tpl-"
  machine_type = var.machine_type
  region       = var.region

  disk {
    source_image = "projects/debian-cloud/global/images/family/debian-12"
    auto_delete  = true
    boot         = true
    disk_type    = "pd-balanced"
    disk_size_gb = 30
  }

  network_interface {
    subnetwork = google_compute_subnetwork.app_subnet.id
    nic_type   = "GVNIC"
    # 공인 IP 미할당 (Private VM 보안 베이스라인)
  }

  service_account {
    email  = google_service_account.app_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin     = "TRUE"
    enable-serial-port = "TRUE"
    app_version        = var.app_version
    keepalive_sec      = tostring(var.keepalive_timeout_sec)
    startup-script     = <<-EOF
      #!/bin/bash
      set -e
      APP_VER=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/app_version" -H "Metadata-Flavor: Google" || echo "v1")
      KA_SEC=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/keepalive_sec" -H "Metadata-Flavor: Google" || echo "620")
      ZONE=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/zone" -H "Metadata-Flavor: Google" | awk -F/ '{print $NF}')
      HOSTNAME=$(hostname)

      cat << 'PYEOF' > /usr/local/bin/app_server.py
      import http.server
      import json
      import os
      import socket
      import time

      PORT = 8080
      APP_VER = os.environ.get("APP_VER", "v1")
      ZONE = os.environ.get("ZONE", "unknown")
      HOSTNAME = socket.gethostname()
      KA_SEC = int(os.environ.get("KA_SEC", "620"))

      class Handler(http.server.BaseHTTPRequestHandler):
          protocol_version = "HTTP/1.1"

          def setup(self):
              super().setup()
              self.request.settimeout(KA_SEC)

          def _send_json(self, code, payload):
              body = json.dumps(payload).encode("utf-8")
              self.send_response(code)
              self.send_header("Content-Type", "application/json")
              self.send_header("Content-Length", str(len(body)))
              self.send_header("Keep-Alive", f"timeout={KA_SEC}, max=10000")
              self.end_headers()
              self.wfile.write(body)

          def do_GET(self):
              if self.path == "/healthz/live":
                  self._send_json(200, {"status": "alive", "instance": HOSTNAME})
              elif self.path == "/healthz/ready":
                  if os.path.exists("/tmp/unready"):
                      self._send_json(503, {"status": "not_ready", "instance": HOSTNAME})
                  else:
                      self._send_json(200, {"status": "ready", "instance": HOSTNAME})
              else:
                  self._send_json(200, {
                      "version": APP_VER,
                      "instance": HOSTNAME,
                      "zone": ZONE,
                      "keepalive_timeout_sec": KA_SEC,
                      "client_header_xff": self.headers.get("X-Forwarded-For", "direct"),
                      "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
                  })

          def do_POST(self):
              length = int(self.headers.get("Content-Length", 0))
              if length > 0:
                  _ = self.rfile.read(length)
              self.do_GET()

      if __name__ == "__main__":
          http.server.ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
      PYEOF

      cat << SYSEOF > /etc/systemd/system/workshop-app.service
      [Unit]
      Description=GCE Workshop HTTP/1.1 Keep-Alive Demo Server
      After=network.target

      [Service]
      Environment="APP_VER=$${APP_VER}"
      Environment="ZONE=$${ZONE}"
      Environment="KA_SEC=$${KA_SEC}"
      ExecStart=/usr/bin/python3 /usr/local/bin/app_server.py
      Restart=always
      RestartSec=2

      [Install]
      WantedBy=multi-user.target
      SYSEOF

      systemctl daemon-reload
      systemctl enable --now workshop-app.service
    EOF
  }

  lifecycle {
    create_before_destroy = true
  }
}

# 6. Regional Managed Instance Group (무중단 배포 및 Autohealing 설정)
resource "google_compute_region_instance_group_manager" "app_mig" {
  name                      = "${var.prefix}-rmig"
  base_instance_name        = "${var.prefix}-vm"
  region                    = var.region
  distribution_policy_zones = var.zones
  distribution_policy_target_shape = "EVEN"

  version {
    name              = "primary"
    instance_template = google_compute_instance_template.app_v1.id
  }

  named_port {
    name = "http"
    port = 8080
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.autoheal_live_hc.id
    initial_delay_sec = 120
  }

  update_policy {
    type                         = "PROACTIVE"
    instance_redistribution_type = "PROACTIVE"
    minimal_action               = "REPLACE"
    most_disruptive_allowed_action = "REPLACE"
    replacement_method           = "SUBSTITUTE"
    max_surge_fixed              = 3
    max_unavailable_fixed        = 0
    min_ready_sec                = 15
  }

  target_size = var.target_size
}

# 7. Global External Application Load Balancer (EXTERNAL_MANAGED - Envoy 기반)
resource "google_compute_global_address" "alb_vip" {
  name = "${var.prefix}-alb-vip"
}

resource "google_compute_backend_service" "app_backend" {
  name                  = "${var.prefix}-backend-svc"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 30
  connection_draining_timeout_sec = 60
  health_checks         = [google_compute_health_check.lb_ready_hc.id]

  backend {
    group           = google_compute_region_instance_group_manager.app_mig.instance_group
    balancing_mode  = "RATE"
    max_rate_per_instance = 500
    capacity_scaler = 1.0
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

resource "google_compute_url_map" "url_map" {
  name            = "${var.prefix}-url-map"
  default_service = google_compute_backend_service.app_backend.id
}

resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "${var.prefix}-http-proxy"
  url_map = google_compute_url_map.url_map.id
}

resource "google_compute_global_forwarding_rule" "http_fwd_rule" {
  name                  = "${var.prefix}-http-fwd-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.http_proxy.id
  ip_address            = google_compute_global_address.alb_vip.id
}
