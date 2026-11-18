output "bucket_urls" {
  description = "gs:// URL per bucket, e.g. gs://<project>-staging-siem-log-archive"
  value       = module.cloud_storage.bucket_urls
}
