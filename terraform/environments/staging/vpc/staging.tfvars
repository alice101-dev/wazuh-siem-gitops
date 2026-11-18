region = "asia-southeast2"
zone   = "asia-southeast2-a"
env    = "staging"

network_vpc_name = "vpc-siem"
subnets = {
  gke = {
    ip_cidr_range = "10.130.0.0/20"
    region        = "asia-southeast2"
  }
}
