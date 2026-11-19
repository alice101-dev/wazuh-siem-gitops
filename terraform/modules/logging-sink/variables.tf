variable "project_id" {
  description = "GCP project ID; sinks are created on this project only, never on a folder or the organization"
  type        = string
}

variable "sinks" {
  description = "Project log sinks keyed by name. destination_name is a Pub/Sub topic name in the same project or a Cloud Storage bucket name. The writer identity is the project's Cloud Logging service agent; the destination's own workspace grants it publish or object-create rights, so the right outlives the sink and log entries still in flight when the sink is deleted are delivered."
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
