variable "project_id" {
  description = "GCP project ID whose Data Access audit logs are configured"
  type        = string
}

variable "audit_configs" {
  description = "Data Access audit log types per service (e.g. iam.googleapis.com). Admin Activity logs are always on and not configured here. Authoritative per listed service."
  type = map(object({
    log_types        = list(string)
    exempted_members = optional(list(string), [])
  }))
  default = {}

  validation {
    condition = alltrue(flatten([
      for c in values(var.audit_configs) : [for t in c.log_types : contains(["ADMIN_READ", "DATA_READ", "DATA_WRITE"], t)]
    ]))
    error_message = "log_types must be ADMIN_READ, DATA_READ or DATA_WRITE."
  }

  validation {
    condition     = !contains(keys(var.audit_configs), "iamcredentials.googleapis.com")
    error_message = "iamcredentials.googleapis.com has no audit config of its own: its Data Access logs (GenerateAccessToken, SignBlob, SignJwt, GenerateIdToken) follow the DATA_READ setting of iam.googleapis.com."
  }

  validation {
    condition     = !contains(keys(var.audit_configs), "pubsub.googleapis.com")
    error_message = "Do not enable Data Access logs for pubsub.googleapis.com: every pull of the SIEM collector would create a log that the sink sends back to Pub/Sub."
  }
}
