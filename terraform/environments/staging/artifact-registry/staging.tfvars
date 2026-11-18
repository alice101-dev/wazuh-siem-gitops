region = "asia-southeast2"
zone   = "asia-southeast2-a"
env    = "staging"

repositories = {
  "siem" = {
    format                 = "DOCKER"
    description            = "Images of the SIEM components built in this repository"
    immutable_tags         = true
    vulnerability_scanning = "DISABLED"

    cleanup_policies = {
      "delete-old" = {
        action    = "DELETE"
        condition = { tag_state = "ANY", older_than = "2592000s" }
      }
      "keep-recent" = {
        action               = "KEEP"
        most_recent_versions = { keep_count = 10 }
      }
    }
  }
}
