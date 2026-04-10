terraform {
  backend "gcs" {
    bucket = "gearsnitch-terraform-state"
    prefix = "terraform/state"
  }
}

data "google_project" "project" {
  project_id = var.project_id
}

# Enable required APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudbuild.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# Service account for Cloud Run services
resource "google_service_account" "cloud_run" {
  account_id   = "gearsnitch-cloud-run"
  display_name = "GearSnitch Cloud Run Service Account"
  project      = var.project_id
}

# Grant Secret Manager access to the service account
resource "google_project_iam_member" "cloud_run_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

locals {
  image_prefix     = "${var.region}-docker.pkg.dev/${var.project_id}/gearsnitch"
  placeholder_image = "us-docker.pkg.dev/cloudrun/container/hello"
  api_image        = var.use_placeholder_images ? local.placeholder_image : "${local.image_prefix}/api:latest"
  web_image        = var.use_placeholder_images ? local.placeholder_image : "${local.image_prefix}/web:latest"
  worker_image     = var.use_placeholder_images ? local.placeholder_image : "${local.image_prefix}/worker:latest"
  realtime_image   = var.use_placeholder_images ? local.placeholder_image : "${local.image_prefix}/realtime:latest"
  labels = {
    environment = var.environment
    managed_by  = "terraform"
    project     = "gearsnitch"
  }
}
