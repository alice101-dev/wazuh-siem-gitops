locals {
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
      exclusions       = s.exclusions
    }
  }
}
