resource "google_cloud_run_v2_service" "api" {
  name     = "gearsnitch-api"
  location = var.region
  project  = var.project_id

  labels = local.labels

  template {
    service_account = google_service_account.cloud_run.email

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      image = local.api_image

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      ports {
        container_port = var.use_placeholder_images ? 8080 : 3000
      }

      startup_probe {
        tcp_socket {
          port = var.use_placeholder_images ? 8080 : 3000
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
        name  = "CORS_ORIGINS"
        value = join(",", distinct([
          "https://${var.domain}",
          "https://www.${var.domain}",
          "http://localhost:3000",
          "http://localhost:5173",
        ]))
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
        name = "JWT_PRIVATE_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.secrets["jwt-private-key"].secret_id
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

      env {
        name = "GOOGLE_OAUTH_CLIENT_ID"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.secrets["google-oauth-client-id"].secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "GOOGLE_OAUTH_CLIENT_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.secrets["google-oauth-client-secret"].secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "APPLE_CLIENT_ID"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.secrets["apple-client-id"].secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "APPLE_TEAM_ID"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.secrets["apple-team-id"].secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "APPLE_KEY_ID"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.secrets["apple-key-id"].secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "APPLE_PRIVATE_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.secrets["apple-private-key"].secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "ENCRYPTION_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.secrets["encryption-key"].secret_id
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

# Note: allUsers IAM blocked by org policy. Use Cloud Run ingress settings
# or domain mapping with Cloudflare for public access.
