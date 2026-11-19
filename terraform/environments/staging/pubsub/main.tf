data "google_project" "this" {
  project_id = var.project_id
}

# The project's Cloud Logging service agent, the writer identity of every sink with a unique writer identity.
data "google_logging_project_settings" "this" {
  project = var.project_id
}

locals {
  log_sink_writer = "serviceAccount:${data.google_logging_project_settings.this.logging_service_account_id}"
  wi_subject      = "principal://iam.googleapis.com/projects/${data.google_project.this.number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject"

  subscriber_accounts = toset(flatten([
    for t in values(var.topics) : [for s in values(t.subscriptions) : s.service_accounts]
  ]))
}

data "google_service_account" "subscriber" {
  for_each   = local.subscriber_accounts
  account_id = "${var.env}-${each.key}"
}

module "pubsub" {
  source = "../../../modules/pubsub"

  project_id = var.project_id
  region     = var.region
  env        = var.env
  topics = {
    for t, topic in var.topics : "${var.env}-${t}" => {
      message_retention_duration = topic.message_retention_duration
      iam = concat(
        [for w in topic.workload_identity_publishers : { role = "roles/pubsub.publisher", member = "${local.wi_subject}/ns/${w.namespace}/sa/${w.service_account}" }],
        topic.log_sink_writer ? [{ role = "roles/pubsub.publisher", member = local.log_sink_writer }] : [],
      )
      subscriptions = {
        for s, sub in topic.subscriptions : "${var.env}-${s}" => {
          ack_deadline_seconds       = sub.ack_deadline_seconds
          message_retention_duration = sub.message_retention_duration
          dead_letter                = sub.dead_letter
          iam = concat(
            [for a in sub.service_accounts : { role = "roles/pubsub.subscriber", member = data.google_service_account.subscriber[a].member }],
            [for w in sub.workload_identity : { role = "roles/pubsub.subscriber", member = "${local.wi_subject}/ns/${w.namespace}/sa/${w.service_account}" }],
          )
        }
      }
    }
  }
}
