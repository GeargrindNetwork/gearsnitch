resource "google_cloud_run_v2_service" "web" {
  name     = "gearsnitch-web"
  location = var.region
  project  = var.project_id

  labels = local.labels

  template {
    service_account = google_service_account.cloud_run.email

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    containers {
      image = "${local.image_prefix}/web:latest"

      resources {
        limits = {
          cpu    = "1"
          memory = "256Mi"
        }
      }

      ports {
        container_port = 80
      }

      startup_probe {
        http_get {
          path = "/"
          port = 80
        }
        initial_delay_seconds = 3
        period_seconds        = 5
        failure_threshold     = 3
      }

      liveness_probe {
        http_get {
          path = "/"
          port = 80
        }
        period_seconds    = 30
        failure_threshold = 3
      }

      env {
        name  = "VITE_API_URL"
        value = google_cloud_run_v2_service.api.uri
      }

      env {
        name  = "VITE_WS_URL"
        value = google_cloud_run_v2_service.realtime.uri
      }
    }
  }

  depends_on = [
    google_project_service.apis["run.googleapis.com"],
  ]
}

# Allow unauthenticated access to the web frontend
resource "google_cloud_run_v2_service_iam_member" "web_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.web.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
