variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "gearsnitch"
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "domain" {
  description = "Primary domain for the application"
  type        = string
  default     = "gearsnitch.com"
}

variable "mongodb_uri" {
  description = "MongoDB Atlas connection URI"
  type        = string
  sensitive   = true
}

variable "redis_url" {
  description = "Redis connection URL"
  type        = string
  sensitive   = true
}

variable "use_placeholder_images" {
  description = "Use Google sample container images for initial deploy before real images are built"
  type        = bool
  default     = true
}
