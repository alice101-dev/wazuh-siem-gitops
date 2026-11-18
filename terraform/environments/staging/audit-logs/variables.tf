variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Primary GCP region"
  type        = string
}

variable "zone" {
  description = "Primary GCP zone (provider only)"
  type        = string
}

variable "audit_configs" {
  description = "Data Access audit log types per service; Admin Activity, System Event and Policy Denied logs are always on"
  type = map(object({
    log_types        = list(string)
    exempted_members = optional(list(string), [])
  }))
  default = {}
}
