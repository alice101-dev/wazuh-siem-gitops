output "key_ring_id" {
  description = "Key ring ID (projects/<p>/locations/<loc>/keyRings/<name>)"
  value       = google_kms_key_ring.ring.id
}

output "crypto_key_ids" {
  description = "Crypto key ID per key name"
  value       = { for k, v in google_kms_crypto_key.key : k => v.id }
}
