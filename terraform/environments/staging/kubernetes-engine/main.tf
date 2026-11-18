data "google_compute_network" "vpc" {
  name = "${var.env}-${var.network_vpc_name}"
}

data "google_compute_subnetwork" "subnet" {
  name   = "${var.env}-${var.network_vpc_name}-${var.subnet_key}-subnet"
  region = var.region
}

data "google_kms_key_ring" "siem" {
  name     = "${var.env}-${var.kms_key_ring}"
  location = var.region
}

data "google_kms_crypto_key" "secrets" {
  name     = var.secrets_encryption_key
  key_ring = data.google_kms_key_ring.siem.id
}

data "google_kms_crypto_key" "boot_disks" {
  name     = var.boot_disk_encryption_key
  key_ring = data.google_kms_key_ring.siem.id
}

module "gke" {
  source     = "../../../modules/kubernetes-engine"
  project_id = var.project_id
  env        = var.env

  location     = var.regional_cluster ? var.region : var.zone
  cluster_name = "${var.env}-${var.cluster_name}"
  vpc_id       = data.google_compute_network.vpc.id
  subnet_id    = data.google_compute_subnetwork.subnet.id

  master_ipv4_cidr_block     = var.master_ipv4_cidr_block
  cluster_ipv4_cidr_block    = var.cluster_ipv4_cidr_block
  services_ipv4_cidr_block   = var.services_ipv4_cidr_block
  master_authorized_networks = var.master_authorized_networks
  release_channel            = var.release_channel
  maintenance_start_time     = var.maintenance_start_time
  maintenance_recurrence     = var.maintenance_recurrence

  sa_account_id   = "${var.env}-${var.sa_account_id}"
  sa_display_name = var.sa_display_name

  database_encryption_key = data.google_kms_crypto_key.secrets.id
  boot_disk_kms_key       = data.google_kms_crypto_key.boot_disks.id

  node_pools = var.node_pools
}
