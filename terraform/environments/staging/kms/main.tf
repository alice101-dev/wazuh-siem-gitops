data "google_project" "this" {
  project_id = var.project_id
}

locals {
  service_agent_domains = {
    "container-engine-robot" = "container-engine-robot.iam.gserviceaccount.com"
    "compute-system"         = "compute-system.iam.gserviceaccount.com"
  }
}

module "kms" {
  source = "../../../modules/kms"

  project_id    = var.project_id
  location      = var.region
  env           = var.env
  key_ring_name = "${var.env}-${var.key_ring_name}"
  crypto_keys = {
    for k, key in var.crypto_keys : k => {
      rotation_period  = key.rotation_period
      protection_level = key.protection_level
      labels           = key.labels
      iam = [
        for g in key.service_agents : {
          role   = g.role
          member = "serviceAccount:service-${data.google_project.this.number}@${local.service_agent_domains[g.agent]}"
        }
      ]
    }
  }
}
