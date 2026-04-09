output "api_url" {
  description = "GearSnitch API service URL"
  value       = google_cloud_run_v2_service.api.uri
}

output "web_url" {
  description = "GearSnitch Web frontend URL"
  value       = google_cloud_run_v2_service.web.uri
}

output "realtime_url" {
  description = "GearSnitch Realtime WebSocket service URL"
  value       = google_cloud_run_v2_service.realtime.uri
}

output "worker_url" {
  description = "GearSnitch Worker service URL (internal only)"
  value       = google_cloud_run_v2_service.worker.uri
}

output "artifact_registry_url" {
  description = "Artifact Registry repository URL"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.gearsnitch.repository_id}"
}
