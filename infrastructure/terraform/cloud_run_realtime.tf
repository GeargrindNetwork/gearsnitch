resource "google_cloud_run_v2_service" "realtime" {
  name     = "gearsnitch-realtime"
  location = var.region
  project  = var.project_id

  labels = local.labels

  template {
    service_account = google_service_account.cloud_run.email

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    # Session affinity for WebSocket connections
    session_affinity = true

    containers {
      image = local.realtime_image

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      ports {
        container_port = var.use_placeholder_images ? 8080 : 3001
      }

      startup_probe {
        tcp_socket {
          port = var.use_placeholder_images ? 8080 : 3001
        }
        initial_delay_seconds = 5
        period_seconds        = 10
        failure_threshold     = 3
      }

      env {
        name  = "NODE_ENV"
        value = var.environment
      }

      env {
        name = "MONGODB_URI"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.secrets["mongodb-uri"].secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "REDIS_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.secrets["redis-url"].secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "JWT_PUBLIC_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.secrets["jwt-public-key"].secret_id
            version = "latest"
          }
        }
      }
    }
  }

  depends_on = [
    google_project_service.apis["run.googleapis.com"],
  ]
}

# Note: allUsers IAM blocked by org policy. Use Cloud Run ingress settings.
