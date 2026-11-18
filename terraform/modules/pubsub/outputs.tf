output "topic_ids" {
  description = "Topic ID per topic name"
  value       = { for k, v in google_pubsub_topic.topic : k => v.id }
}

output "subscription_ids" {
  description = "Subscription ID per subscription name"
  value       = { for k, v in google_pubsub_subscription.subscription : k => v.id }
}

output "dead_letter_subscription_ids" {
  description = "Dead-letter subscription ID per source subscription"
  value       = { for k, v in google_pubsub_subscription.dead_letter : k => v.id }
}
