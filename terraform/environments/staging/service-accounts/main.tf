module "service_accounts" {
  source = "../../../modules/service-accounts"

  project_id       = var.project_id
  service_accounts = { for k, v in var.service_accounts : "${var.env}-${k}" => v }
}
