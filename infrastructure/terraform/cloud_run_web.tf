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
      image = local.web_image

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      ports {
        container_port = var.use_placeholder_images ? 8080 : 80
      }

      startup_probe {
        tcp_socket {
          port = var.use_placeholder_images ? 8080 : 80
        }
        initial_delay_seconds = 3
        period_seconds        = 5
        failure_threshold     = 3
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

# Note: allUsers IAM blocked by org policy. Use Cloud Run ingress settings.
