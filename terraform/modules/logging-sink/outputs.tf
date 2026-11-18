output "writer_identities" {
  description = "Writer identity per sink"
  value       = { for k, v in google_logging_project_sink.sink : k => v.writer_identity }
}
