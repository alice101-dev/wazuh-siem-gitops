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
}

module "cloud_storage" {
  source = "../../../modules/cloud-storage"

  project_id = var.project_id
  region     = var.region
  env        = var.env
  buckets = {
    for k, b in var.buckets : "${var.project_id}-${var.env}-${k}" => merge(b, {
      iam = concat(
        [for w in b.workload_identity : { role = w.role, member = "${local.wi_subject}/ns/${w.namespace}/sa/${w.service_account}" }],
        b.log_sink_writer ? [{ role = "roles/storage.objectCreator", member = local.log_sink_writer }] : [],
      )
    })
  }
}
