output "emails" {
  description = "Service account email per account_id"
  value       = { for k, v in google_service_account.sa : k => v.email }
}
