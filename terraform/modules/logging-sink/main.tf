locals {
  destinations = {
    pubsub  = "pubsub.googleapis.com/projects/%s/topics/%s"
    storage = "storage.googleapis.com/%s"
  }

  pubsub_sinks  = { for name, s in var.sinks : name => s if s.destination_type == "pubsub" }
  storage_sinks = { for name, s in var.sinks : name => s if s.destination_type == "storage" }
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

resource "time_sleep" "writer_identity_propagation" {
  for_each = var.sinks

  create_duration = var.writer_identity_propagation

  triggers = {
    writer_identity = google_logging_project_sink.sink[each.key].writer_identity
  }
}

resource "google_pubsub_topic_iam_member" "writer" {
  for_each = local.pubsub_sinks

  project = var.project_id
  topic   = each.value.destination_name
  role    = "roles/pubsub.publisher"
  member  = time_sleep.writer_identity_propagation[each.key].triggers.writer_identity
}

resource "google_storage_bucket_iam_member" "writer" {
  for_each = local.storage_sinks

  bucket = each.value.destination_name
  role   = "roles/storage.objectCreator"
  member = time_sleep.writer_identity_propagation[each.key].triggers.writer_identity
}
