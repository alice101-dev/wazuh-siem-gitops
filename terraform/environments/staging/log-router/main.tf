locals {
  k8s_data_access_noise = var.k8s_data_access_noise_filter == "" ? [] : [{
    name        = "k8s-data-access-noise"
    description = "Kubernetes Data Access logs other than secret reads, nodes/proxy and TokenRequests by principals outside the cluster system"
    filter      = var.k8s_data_access_noise_filter
  }]

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
      exclusions       = concat(s.exclusions, local.k8s_data_access_noise)
    }
  }
}

# The _Default bucket would ingest, and bill, every Kubernetes read; only the kept ones are stored.
resource "google_logging_project_exclusion" "k8s_data_access_noise" {
  count = length(local.k8s_data_access_noise)

  project     = var.project_id
  name        = "${var.env}-${local.k8s_data_access_noise[0].name}"
  description = local.k8s_data_access_noise[0].description
  filter      = local.k8s_data_access_noise[0].filter
}
