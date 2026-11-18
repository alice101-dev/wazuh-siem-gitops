locals {
  labels = {
    env        = var.env
    managed_by = "terraform"
  }

  key_iam = merge([
    for key, k in var.crypto_keys : {
      for binding in k.iam : "${key}|${binding.role}|${binding.member}" => merge(binding, { key = key })
    }
  ]...)
}

resource "google_kms_key_ring" "ring" {
  project  = var.project_id
  name     = var.key_ring_name
  location = var.location

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_kms_crypto_key" "key" {
  for_each = var.crypto_keys

  name            = each.key
  key_ring        = google_kms_key_ring.ring.id
  purpose         = "ENCRYPT_DECRYPT"
  rotation_period = each.value.rotation_period
  labels          = merge(local.labels, each.value.labels)

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = each.value.protection_level
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_kms_crypto_key_iam_member" "member" {
  for_each = local.key_iam

  crypto_key_id = google_kms_crypto_key.key[each.value.key].id
  role          = each.value.role
  member        = each.value.member
}
