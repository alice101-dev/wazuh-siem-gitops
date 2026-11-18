region = "asia-southeast2"
zone   = "asia-southeast2-a"
env    = "staging"

topics = {
  "siem-gcp-logs" = {
    subscriptions = {
      "siem-wazuh" = {
        ack_deadline_seconds       = 60
        message_retention_duration = "604800s"
        dead_letter                = { max_delivery_attempts = 10 }
        service_accounts           = ["siem-gcp-collector"]
      }
    }
  }
}
