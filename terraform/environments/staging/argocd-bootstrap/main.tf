locals {
  image_registry   = "${var.region}-docker.pkg.dev/${var.project_id}/${var.env}-${var.image_repository}"
  gcp_subscription = "${var.env}-${var.gcp_subscription}"
}

data "google_kms_key_ring" "siem" {
  name     = "${var.env}-${var.kms_key_ring}"
  location = var.region
}

data "google_kms_crypto_key" "volumes" {
  name     = var.volume_encryption_key
  key_ring = data.google_kms_key_ring.siem.id
}

data "google_pubsub_subscription" "collector" {
  name = local.gcp_subscription
}

module "argocd" {
  source = "../../../modules/argocd-bootstrap"

  argocd_chart_version      = var.argocd_chart_version
  argocd_apps_chart_version = var.argocd_apps_chart_version

  gitops_repo_url        = var.gitops_repo_url
  gitops_target_revision = var.gitops_target_revision
  gitops_repo_username   = var.gitops_repo_username
  gitops_repo_password   = var.gitops_repo_password

  root_application_file = "${path.root}/../../../../bootstrap/root.yaml"

  cluster_labels = merge(
    { env = var.env },
    { for name in var.enabled_components : "enable_${name}" => "true" },
  )
  cluster_annotations = {
    "platform/project-id"       = var.project_id
    "platform/image-registry"   = local.image_registry
    "platform/gcp-subscription" = data.google_pubsub_subscription.collector.name
    "platform/volume-kms-key"   = data.google_kms_crypto_key.volumes.id
  }
}
