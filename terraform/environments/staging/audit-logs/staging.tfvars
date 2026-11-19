region = "asia-southeast2"
zone   = "asia-southeast2-a"

audit_configs = {
  # Kubernetes API reads (secrets, nodes/proxy) and TokenRequests; log-router drops all but those.
  "container.googleapis.com" = {
    log_types = ["DATA_READ", "DATA_WRITE"]
  }
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
