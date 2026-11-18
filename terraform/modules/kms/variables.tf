variable "project_id" {
  description = "GCP project ID that holds the key ring"
  type        = string
}

variable "location" {
  description = "Key ring location: the region of the GKE cluster (a zonal cluster uses its region; global is not supported by GKE)"
  type        = string

  validation {
    condition     = var.location != "global"
    error_message = "GKE does not support Cloud KMS keys in the global location."
  }
}

variable "env" {
  description = "Environment name, used as a label"
  type        = string
}

variable "key_ring_name" {
  description = "Key ring name, already env-prefixed (e.g. staging-siem). Key rings and keys cannot be deleted."
  type        = string
}

variable "crypto_keys" {
  description = "Symmetric encryption keys keyed by name; iam grants roles on each key (e.g. to Google service agents)."
  type = map(object({
    rotation_period  = optional(string)
    protection_level = optional(string, "SOFTWARE")
    labels           = optional(map(string), {})
    iam = optional(list(object({
      role   = string
      member = string
    })), [])
  }))

  validation {
    condition     = alltrue([for k in values(var.crypto_keys) : contains(["SOFTWARE", "HSM"], k.protection_level)])
    error_message = "protection_level must be SOFTWARE or HSM."
  }

  validation {
    condition     = alltrue([for k in values(var.crypto_keys) : k.rotation_period == null || can(regex("^[0-9]+s$", k.rotation_period))])
    error_message = "rotation_period must be a duration in seconds, e.g. 7776000s (90 days)."
  }
}
