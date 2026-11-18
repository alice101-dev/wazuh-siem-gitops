module "audit_config" {
  source = "../../../modules/audit-config"

  project_id    = var.project_id
  audit_configs = var.audit_configs
}
