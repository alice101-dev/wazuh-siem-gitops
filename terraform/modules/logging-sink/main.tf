locals {
  destinations = {
    pubsub  = "pubsub.googleapis.com/projects/%s/topics/%s"
    storage = "storage.googleapis.com/%s"
  }
}

resource "google_logging_project_sink" "sink" {
  for_each = var.sinks

  project     = var.project_id
  name        = each.key
  description = each.value.description
  filter      = each.value.filter
  destination = (each.value.destination_type == "pubsub"
    ? format(local.destinations.pubsub, var.project_id, each.value.destination_name)
    : format(local.destinations.storage, each.value.destination_name)
  )
  unique_writer_identity = true

  dynamic "exclusions" {
    for_each = each.value.exclusions
    content {
      name        = exclusions.value.name
      description = exclusions.value.description
      filter      = exclusions.value.filter
    }
  }
}
