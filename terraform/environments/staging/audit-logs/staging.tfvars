region = "asia-southeast2"
zone   = "asia-southeast2-a"

audit_configs = {
  "iam.googleapis.com" = {
    log_types = ["ADMIN_READ", "DATA_READ", "DATA_WRITE"]
  }
  "secretmanager.googleapis.com" = {
    log_types = ["ADMIN_READ", "DATA_READ", "DATA_WRITE"]
  }
  "cloudkms.googleapis.com" = {
    log_types = ["ADMIN_READ", "DATA_READ", "DATA_WRITE"]
  }
}
