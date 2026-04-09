resource "google_artifact_registry_repository" "gearsnitch" {
  location      = var.region
  repository_id = "gearsnitch"
  description   = "Docker images for GearSnitch services"
  format        = "DOCKER"
  project       = var.project_id

  labels = local.labels

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"

    most_recent_versions {
      keep_count = 10
    }
  }

  depends_on = [
    google_project_service.apis["artifactregistry.googleapis.com"],
  ]
}
