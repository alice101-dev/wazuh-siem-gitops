output "topic_ids" {
  description = "Topic ID per topic"
  value       = module.pubsub.topic_ids
}

output "subscription_ids" {
  description = "Subscription ID per subscription"
  value       = module.pubsub.subscription_ids
}

output "dead_letter_subscription_ids" {
  description = "Dead-letter subscription per source subscription; messages land here after max_delivery_attempts"
  value       = module.pubsub.dead_letter_subscription_ids
}
