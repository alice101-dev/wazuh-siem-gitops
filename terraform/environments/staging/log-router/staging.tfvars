region = "asia-southeast2"
zone   = "asia-southeast2-a"
env    = "staging"

security_log_filter = <<-EOT
  log_id("cloudaudit.googleapis.com/activity")
  OR log_id("cloudaudit.googleapis.com/data_access")
  OR log_id("cloudaudit.googleapis.com/system_event")
  OR log_id("cloudaudit.googleapis.com/policy")
  OR log_id("cloudaudit.googleapis.com/access_transparency")
  OR log_id("compute.googleapis.com/firewall")
EOT

sinks = {
  "siem-wazuh" = {
    destination_type = "pubsub"
    destination_name = "siem-gcp-logs"
    description      = "Security logs of this project to the Wazuh SIEM through Pub/Sub"
    exclusions = [{
      name        = "k8s-system-lease-renewals"
      description = "Leader-election lease renewals of GKE system components: high volume, no security value"
      filter      = "protoPayload.methodName=\"io.k8s.coordination.v1.leases.update\" AND protoPayload.authenticationInfo.principalEmail=~\"^system:\""
    }]
  }
  "siem-archive" = {
    destination_type = "storage"
    destination_name = "siem-log-archive"
    description      = "Raw copy of the same security logs to Cloud Storage, independent of the SIEM"
    exclusions = [{
      name        = "k8s-system-lease-renewals"
      description = "Leader-election lease renewals of GKE system components: high volume, no security value"
      filter      = "protoPayload.methodName=\"io.k8s.coordination.v1.leases.update\" AND protoPayload.authenticationInfo.principalEmail=~\"^system:\""
    }]
  }
}
