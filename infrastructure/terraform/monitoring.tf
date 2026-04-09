# High error rate alert — triggers when 5xx rate exceeds 5% over 5 minutes
resource "google_monitoring_alert_policy" "high_error_rate" {
  display_name = "GearSnitch API High Error Rate"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Cloud Run 5xx error rate > 5%"

    condition_threshold {
      filter          = "resource.type = \"cloud_run_revision\" AND resource.labels.service_name = \"gearsnitch-api\" AND metric.type = \"run.googleapis.com/request_count\" AND metric.labels.response_code_class = \"5xx\""
      comparison      = "COMPARISON_GT"
      threshold_value = 5
      duration        = "300s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  notification_channels = []

  alert_strategy {
    auto_close = "1800s"
  }

  depends_on = [
    google_project_service.apis["monitoring.googleapis.com"],
  ]
}

# High latency alert — triggers when p95 latency exceeds 2 seconds
resource "google_monitoring_alert_policy" "high_latency" {
  display_name = "GearSnitch API High Latency"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Cloud Run p95 latency > 2s"

    condition_threshold {
      filter          = "resource.type = \"cloud_run_revision\" AND resource.labels.service_name = \"gearsnitch-api\" AND metric.type = \"run.googleapis.com/request_latencies\""
      comparison      = "COMPARISON_GT"
      threshold_value = 2000
      duration        = "300s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_PERCENTILE_95"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  notification_channels = []

  alert_strategy {
    auto_close = "1800s"
  }

  depends_on = [
    google_project_service.apis["monitoring.googleapis.com"],
  ]
}

# Worker instance count alert — triggers when worker has pending instances (queue backlog proxy)
resource "google_monitoring_alert_policy" "worker_backlog" {
  display_name = "GearSnitch Worker Queue Backlog"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Worker instance count at max for 10 minutes"

    condition_threshold {
      filter          = "resource.type = \"cloud_run_revision\" AND resource.labels.service_name = \"gearsnitch-worker\" AND metric.type = \"run.googleapis.com/container/instance_count\""
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "600s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_MAX"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  notification_channels = []

  alert_strategy {
    auto_close = "1800s"
  }

  depends_on = [
    google_project_service.apis["monitoring.googleapis.com"],
  ]
}
