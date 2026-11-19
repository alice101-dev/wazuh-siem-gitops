region = "asia-southeast2"
zone   = "asia-southeast2-a"
env    = "staging"

buckets = {
  "siem-log-archive" = {
    storage_class                 = "STANDARD"
    soft_delete_retention_seconds = 604800
    log_sink_writer               = true
    lifecycle_rules = [
      { action = "Delete", age_days = 365 },
      { action = "AbortIncompleteMultipartUpload", age_days = 1 },
    ]
  }
}
