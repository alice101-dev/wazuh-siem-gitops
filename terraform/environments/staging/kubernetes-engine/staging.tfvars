region = "asia-southeast2"
zone   = "asia-southeast2-a"
env    = "staging"

network_vpc_name = "vpc-siem"
subnet_key       = "gke"

cluster_name     = "siem"
regional_cluster = false
release_channel  = "STABLE"

master_ipv4_cidr_block   = "10.0.4.0/28"
cluster_ipv4_cidr_block  = "10.134.0.0/16"
services_ipv4_cidr_block = "10.135.0.0/22"

master_authorized_networks = [
  { cidr_block = "10.130.0.0/20", display_name = "vpc-internal" },
]

maintenance_start_time = "2026-01-04T18:00:00Z"
maintenance_recurrence = "FREQ=WEEKLY;BYDAY=SU,MO,TU,WE"

kms_key_ring             = "siem"
secrets_encryption_key   = "gke-secrets"
boot_disk_encryption_key = "gke-disks"

sa_account_id   = "siem-gke"
sa_display_name = "GKE node SA staging-siem"

node_pools = {
  "general" = {
    machine_type   = "e2-standard-4"
    min_node_count = 1
    max_node_count = 3
    spot           = true
    disk_size_gb   = 50
    disk_type      = "pd-standard"
    labels         = { "workload" = "general" }
    tags           = ["staging-siem-node"]
  }
  "siem" = {
    machine_type   = "e2-standard-4"
    min_node_count = 3
    max_node_count = 6
    spot           = true
    disk_size_gb   = 50
    disk_type      = "pd-ssd"
    labels         = { "workload" = "siem" }
    sysctls        = { "vm.max_map_count" = "262144" }
    taints         = [{ key = "workload", value = "siem", effect = "NO_SCHEDULE" }]
    tags           = ["staging-siem-node"]
  }
}
