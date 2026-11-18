region = "asia-southeast2"
zone   = "asia-southeast2-a"
env    = "staging"

key_ring_name = "siem"

crypto_keys = {
  "gke-secrets" = {
    rotation_period = "7776000s"
    service_agents = [
      { agent = "container-engine-robot", role = "roles/cloudkms.cryptoKeyEncrypterDecrypter" },
    ]
  }
  "gke-disks" = {
    rotation_period = "7776000s"
    service_agents = [
      { agent = "compute-system", role = "roles/cloudkms.cryptoKeyEncrypterDecrypter" },
    ]
  }
}
