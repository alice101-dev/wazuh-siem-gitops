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
  description = "Environment name, prefix of topic and subscription names"
  type        = string
}

variable "topics" {
  description = "Topics keyed by base name (without env prefix), each with pull subscriptions keyed by base name. Subscribers are service accounts from the service-accounts workspace (base account_id) or Kubernetes ServiceAccounts through Workload Identity."
  type = map(object({
    message_retention_duration = optional(string)
    subscriptions = optional(map(object({
      ack_deadline_seconds       = optional(number, 60)
      message_retention_duration = optional(string, "604800s")
      dead_letter = optional(object({
        max_delivery_attempts = optional(number, 10)
      }))
      service_accounts = optional(list(string), [])
      workload_identity = optional(list(object({
        namespace       = string
        service_account = string
      })), [])
    })), {})
  }))
  default = {}
}
