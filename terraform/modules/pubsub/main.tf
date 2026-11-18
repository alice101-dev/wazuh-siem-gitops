data "google_project" "this" {
  project_id = var.project_id
}

locals {
  labels = {
    env        = var.env
    managed_by = "terraform"
  }

  pubsub_service_agent = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"

  subscriptions = merge([
    for topic, t in var.topics : {
      for name, s in t.subscriptions : name => merge(s, { topic = topic })
    }
  ]...)

  dead_lettered = { for name, s in local.subscriptions : name => s if s.dead_letter != null }

  topic_iam = merge([
    for topic, t in var.topics : {
      for binding in t.iam : "${topic}|${binding.role}|${binding.member}" => merge(binding, { topic = topic })
    }
  ]...)

  subscription_iam = merge([
    for name, s in local.subscriptions : {
      for binding in s.iam : "${name}|${binding.role}|${binding.member}" => merge(binding, { subscription = name })
    }
  ]...)
}

resource "google_pubsub_topic" "topic" {
  for_each = var.topics

  project                    = var.project_id
  name                       = each.key
  labels                     = merge(local.labels, each.value.labels)
  message_retention_duration = each.value.message_retention_duration

  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
}

resource "google_pubsub_topic" "dead_letter" {
  for_each = local.dead_lettered

  project = var.project_id
  name    = "${each.key}-dead-letter"
  labels  = local.labels

  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
}

resource "google_pubsub_subscription" "dead_letter" {
  for_each = local.dead_lettered

  project                    = var.project_id
  name                       = "${each.key}-dead-letter"
  topic                      = google_pubsub_topic.dead_letter[each.key].id
  labels                     = local.labels
  ack_deadline_seconds       = 60
  message_retention_duration = "604800s"

  expiration_policy {
    ttl = ""
  }
}

resource "google_pubsub_subscription" "subscription" {
  for_each = local.subscriptions

  project                    = var.project_id
  name                       = each.key
  topic                      = google_pubsub_topic.topic[each.value.topic].id
  labels                     = merge(local.labels, each.value.labels)
  ack_deadline_seconds       = each.value.ack_deadline_seconds
  message_retention_duration = each.value.message_retention_duration
  retain_acked_messages      = each.value.retain_acked_messages

  expiration_policy {
    ttl = ""
  }

  retry_policy {
    minimum_backoff = each.value.minimum_backoff
    maximum_backoff = each.value.maximum_backoff
  }

  dynamic "dead_letter_policy" {
    for_each = each.value.dead_letter != null ? [each.value.dead_letter] : []
    content {
      dead_letter_topic     = google_pubsub_topic.dead_letter[each.key].id
      max_delivery_attempts = dead_letter_policy.value.max_delivery_attempts
    }
  }
}

resource "google_pubsub_topic_iam_member" "dead_letter_publisher" {
  for_each = local.dead_lettered

  project = var.project_id
  topic   = google_pubsub_topic.dead_letter[each.key].name
  role    = "roles/pubsub.publisher"
  member  = local.pubsub_service_agent
}

resource "google_pubsub_subscription_iam_member" "dead_letter_subscriber" {
  for_each = local.dead_lettered

  project      = var.project_id
  subscription = google_pubsub_subscription.subscription[each.key].name
  role         = "roles/pubsub.subscriber"
  member       = local.pubsub_service_agent
}

resource "google_pubsub_topic_iam_member" "member" {
  for_each = local.topic_iam

  project = var.project_id
  topic   = google_pubsub_topic.topic[each.value.topic].name
  role    = each.value.role
  member  = each.value.member
}

resource "google_pubsub_subscription_iam_member" "member" {
  for_each = local.subscription_iam

  project      = var.project_id
  subscription = google_pubsub_subscription.subscription[each.value.subscription].name
  role         = each.value.role
  member       = each.value.member
}
