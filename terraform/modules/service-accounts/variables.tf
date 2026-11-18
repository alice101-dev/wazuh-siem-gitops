variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "service_accounts" {
  description = "Service accounts keyed by account_id (6-30 characters, already env-prefixed). Roles are granted on the resources they use, not on the project."
  type = map(object({
    display_name = string
    description  = optional(string, "")
  }))
  default = {}

  validation {
    condition     = alltrue([for id in keys(var.service_accounts) : can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", id))])
    error_message = "account_id must be 6-30 lowercase letters, digits or hyphens, starting with a letter."
  }
}
