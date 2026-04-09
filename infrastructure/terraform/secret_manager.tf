locals {
  secrets = [
    "mongodb-uri",
    "redis-url",
    "jwt-private-key",
    "jwt-public-key",
    "google-oauth-client-id",
    "google-oauth-client-secret",
    "apple-client-id",
    "apple-team-id",
    "apple-key-id",
    "apple-private-key",
    "apns-key",
    "encryption-key",
  ]
}

resource "google_secret_manager_secret" "secrets" {
  for_each  = toset(local.secrets)
  secret_id = each.value
  project   = var.project_id

  labels = local.labels

  replication {
    auto {}
  }

  depends_on = [
    google_project_service.apis["secretmanager.googleapis.com"],
  ]
}

# Secret values are managed outside Terraform (via gcloud CLI or console).
# Terraform manages the secret resource and IAM, not the secret data.
