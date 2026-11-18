variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Only region where messages are stored (message storage policy)"
  type        = string
}

variable "env" {
  description = "Environment name, used as a label"
  type        = string
}

variable "topics" {
  description = "Topics keyed by final name, each with pull subscriptions keyed by final name. dead_letter adds a <subscription>-dead-letter topic and subscription that keep undeliverable messages."
  type = map(object({
    labels                     = optional(map(string), {})
    message_retention_duration = optional(string)
    iam = optional(list(object({
      role   = string
      member = string
    })), [])
    subscriptions = optional(map(object({
      labels                     = optional(map(string), {})
      ack_deadline_seconds       = optional(number, 60)
      message_retention_duration = optional(string, "604800s")
      retain_acked_messages      = optional(bool, false)
      minimum_backoff            = optional(string, "10s")
      maximum_backoff            = optional(string, "600s")
      dead_letter = optional(object({
        max_delivery_attempts = optional(number, 10)
      }))
      iam = optional(list(object({
        role   = string
        member = string
      })), [])
    })), {})
  }))
  default = {}

  validation {
    condition = alltrue(flatten([
      for t in values(var.topics) : [for s in values(t.subscriptions) : s.ack_deadline_seconds >= 10 && s.ack_deadline_seconds <= 600]
    ]))
    error_message = "ack_deadline_seconds must be between 10 and 600."
  }

  validation {
    condition = alltrue(flatten([
      for t in values(var.topics) : [for s in values(t.subscriptions) : s.dead_letter == null ? true : (s.dead_letter.max_delivery_attempts >= 5 && s.dead_letter.max_delivery_attempts <= 100)]
    ]))
    error_message = "dead_letter.max_delivery_attempts must be between 5 and 100."
  }
}
