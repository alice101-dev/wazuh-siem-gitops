variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Primary GCP region, also the key ring location"
  type        = string
}

variable "zone" {
  description = "Primary GCP zone (provider only)"
  type        = string
}

variable "env" {
  description = "Environment name, prefix of the key ring name and a label"
  type        = string
}

variable "key_ring_name" {
  description = "Base key ring name (without env prefix)"
  type        = string
}

variable "crypto_keys" {
  description = "Encryption keys keyed by name; service_agents grants roles to Google service agents of this project (container-engine-robot = GKE, compute-system = Compute Engine)."
  type = map(object({
    rotation_period  = optional(string)
    protection_level = optional(string, "SOFTWARE")
    labels           = optional(map(string), {})
    service_agents = optional(list(object({
      agent = string
      role  = string
    })), [])
  }))

  validation {
    condition = alltrue(flatten([
      for k in values(var.crypto_keys) : [for g in k.service_agents : contains(["container-engine-robot", "compute-system"], g.agent)]
    ]))
    error_message = "service_agents[*].agent must be container-engine-robot or compute-system."
  }
}
