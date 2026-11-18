resource "google_project_iam_audit_config" "config" {
  for_each = var.audit_configs

  project = var.project_id
  service = each.key

  dynamic "audit_log_config" {
    for_each = each.value.log_types
    content {
      log_type         = audit_log_config.value
      exempted_members = each.value.exempted_members
    }
  }
}
