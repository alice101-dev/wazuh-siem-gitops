locals {
  data_access_noise = concat(
    var.k8s_data_access_noise_filter == "" ? [] : [{
      name        = "k8s-data-access-noise"
      description = "Kubernetes Data Access logs other than denied requests, secret reads, nodes/proxy and TokenRequests by principals outside the cluster system"
      filter      = var.k8s_data_access_noise_filter
    }],
    var.admin_read_noise_filter == "" ? [] : [{
      name        = "admin-read-noise"
      description = "Successful reads of the services whose Data Access logs are on only to record denied requests"
      filter      = var.admin_read_noise_filter
    }],
  )

  destination_names = {
    for k, s in var.sinks : k => (s.destination_type == "pubsub"
      ? "${var.env}-${s.destination_name}"
      : "${var.project_id}-${var.env}-${s.destination_name}"
    )
  }
}

data "google_pubsub_topic" "destination" {
  for_each = { for k, s in var.sinks : k => s if s.destination_type == "pubsub" }
  name     = local.destination_names[each.key]
}

data "google_storage_bucket" "destination" {
  for_each = { for k, s in var.sinks : k => s if s.destination_type == "storage" }
  name     = local.destination_names[each.key]
}

module "logging_sink" {
  source = "../../../modules/logging-sink"

  project_id = var.project_id
  sinks = {
    for k, s in var.sinks : "${var.env}-${k}" => {
      destination_type = s.destination_type
      destination_name = s.destination_type == "pubsub" ? data.google_pubsub_topic.destination[k].name : data.google_storage_bucket.destination[k].name
      filter           = coalesce(s.filter, var.security_log_filter)
      description      = s.description
      exclusions       = concat(s.exclusions, local.data_access_noise)
    }
  }
}

# The _Default bucket would ingest, and bill, every read; only the kept ones are stored.
resource "google_logging_project_exclusion" "data_access_noise" {
  for_each = { for e in local.data_access_noise : e.name => e }

  project     = var.project_id
  name        = "${var.env}-${each.key}"
  description = each.value.description
  filter      = each.value.filter
}

moved {
  from = google_logging_project_exclusion.k8s_data_access_noise[0]
  to   = google_logging_project_exclusion.data_access_noise["k8s-data-access-noise"]
}
