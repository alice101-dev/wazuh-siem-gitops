region = "asia-southeast2"
zone   = "asia-southeast2-a"
env    = "staging"

topics = {
  "siem-gcp-logs" = {
    workload_identity_publishers = [{ namespace = "falco", service_account = "falco-falcosidekick" }]
    subscriptions = {
      "siem-wazuh" = {
        ack_deadline_seconds       = 60
        message_retention_duration = "604800s"
        dead_letter                = { max_delivery_attempts = 10 }
        workload_identity          = [{ namespace = "wazuh", service_account = "wazuh-gcp-collector" }]
      }
    }
  }
}
