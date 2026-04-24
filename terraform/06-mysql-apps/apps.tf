resource "random_password" "app" {
  for_each         = var.apps
  length           = 32
  special          = true
  override_special = "!@#$%^&*()-_+="
}

resource "mysql_database" "app" {
  for_each = var.apps
  name     = each.value.database
}

resource "mysql_user" "app" {
  for_each           = var.apps
  user               = each.key
  host               = "%"
  plaintext_password = random_password.app[each.key].result
  tls_option         = "SSL"
}

resource "mysql_grant" "app" {
  for_each   = var.apps
  user       = mysql_user.app[each.key].user
  host       = mysql_user.app[each.key].host
  database   = mysql_database.app[each.key].name
  privileges = ["ALL"]
}

resource "google_secret_manager_secret" "app_user" {
  for_each  = var.apps
  secret_id = "${each.key}-db-user"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "app_pass" {
  for_each  = var.apps
  secret_id = "${each.key}-db-pass"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "app_name" {
  for_each  = var.apps
  secret_id = "${each.key}-db-name"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "app_user" {
  for_each    = var.apps
  secret      = google_secret_manager_secret.app_user[each.key].id
  secret_data = each.key
}

resource "google_secret_manager_secret_version" "app_pass" {
  for_each    = var.apps
  secret      = google_secret_manager_secret.app_pass[each.key].id
  secret_data = random_password.app[each.key].result
}

resource "google_secret_manager_secret_version" "app_name" {
  for_each    = var.apps
  secret      = google_secret_manager_secret.app_name[each.key].id
  secret_data = each.value.database
}

locals {
  app_secret_bindings = {
    for pair in flatten([
      for app, cfg in var.apps : [
        for secret_id in [
          google_secret_manager_secret.app_user[app].secret_id,
          google_secret_manager_secret.app_pass[app].secret_id,
          google_secret_manager_secret.app_name[app].secret_id,
          data.google_secret_manager_secret.db_host.secret_id,
          ] : {
          app    = app
          secret = secret_id
          sa     = cfg.service_account
        }
      ]
    ]) : "${pair.app}-${pair.secret}" => pair
  }
}

resource "google_secret_manager_secret_iam_member" "app_access" {
  for_each  = local.app_secret_bindings
  secret_id = each.value.secret
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${each.value.sa}"
}
