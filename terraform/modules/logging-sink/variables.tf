variable "project_id" {
  description = "GCP project ID; sinks are created on this project only, never on a folder or the organization"
  type        = string
}

variable "sinks" {
  description = "Project log sinks keyed by name. destination_name is a Pub/Sub topic name in the same project or a Cloud Storage bucket name; the sink's writer identity gets publish or object-create rights on it."
  type = map(object({
    destination_type = string
    destination_name = string
    filter           = string
    description      = optional(string, "")
    exclusions = optional(list(object({
      name        = string
      filter      = string
      description = optional(string, "")
    })), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for s in values(var.sinks) : contains(["pubsub", "storage"], s.destination_type)])
    error_message = "destination_type must be pubsub or storage."
  }

  validation {
    condition     = alltrue([for s in values(var.sinks) : trimspace(s.filter) != ""])
    error_message = "Every sink needs a filter; an empty filter would export every log of the project."
  }
}

variable "writer_identity_propagation" {
  description = "Wait after a sink is created before granting its writer identity: the Cloud Logging service agent is created with the first sink of a project and Cloud Storage rejects it until it has propagated"
  type        = string
  default     = "90s"
}
