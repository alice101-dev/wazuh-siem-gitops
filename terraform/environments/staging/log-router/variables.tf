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
  description = "Environment name, prefix of sink, topic and bucket names"
  type        = string
}

variable "security_log_filter" {
  description = "Logging query of the security logs sent to the SIEM, used by every sink that sets no filter of its own"
  type        = string
}

variable "sinks" {
  description = "Project log sinks keyed by base name (without env prefix). destination_name is the base topic name of the pubsub workspace or the bucket key of the cloud-storage workspace."
  type = map(object({
    destination_type = string
    destination_name = string
    filter           = optional(string)
    description      = optional(string, "")
    exclusions = optional(list(object({
      name        = string
      filter      = string
      description = optional(string, "")
    })), [])
  }))
  default = {}
}

variable "k8s_data_access_noise_filter" {
  description = "Logging query of the Kubernetes Data Access logs to drop: excluded from the _Default bucket (no ingestion charge) and from every sink. Empty keeps them all."
  type        = string
  default     = ""
}

variable "admin_read_noise_filter" {
  description = "Logging query of the Data Access logs to drop for services whose logs are on only to record denied requests: excluded from the _Default bucket (no ingestion charge) and from every sink. Empty keeps them all."
  type        = string
  default     = ""
}
