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

variable "env" {
  description = "Environment name, prefix of the account IDs"
  type        = string
}

variable "service_accounts" {
  description = "Service accounts keyed by base account_id (without env prefix)"
  type = map(object({
    display_name = string
    description  = optional(string, "")
  }))
  default = {}
}
