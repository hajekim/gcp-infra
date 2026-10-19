output "alb_vip" {
  description = "Global External Application Load Balancer VIP"
  value       = google_compute_global_address.alb_vip.address
}

output "alb_test_url" {
  description = "트래픽 테스트 엔드포인트 URL"
  value       = "http://${google_compute_global_address.alb_vip.address}/"
}

output "mig_name" {
  description = "생성된 Regional MIG 이름"
  value       = google_compute_region_instance_group_manager.app_mig.name
}

output "active_instance_template" {
  description = "현재 적용된 Instance Template URI"
  value       = google_compute_instance_template.app_v1.self_link
}
