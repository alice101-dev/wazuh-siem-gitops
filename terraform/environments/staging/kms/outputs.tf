output "key_ring_id" {
  description = "Key ring ID"
  value       = module.kms.key_ring_id
}

output "crypto_key_ids" {
  description = "Crypto key ID per key name"
  value       = module.kms.crypto_key_ids
}
