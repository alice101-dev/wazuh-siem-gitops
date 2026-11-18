region = "asia-southeast2"
zone   = "asia-southeast2-a"
env    = "staging"

service_accounts = {
  "siem-gcp-collector" = {
    display_name = "Wazuh GCP Pub/Sub collector"
    description  = "Pulls security logs from the SIEM Pub/Sub subscription; key kept in Secret Manager"
  }
}
