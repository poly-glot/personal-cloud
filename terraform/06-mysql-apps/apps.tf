resource "random_password" "app" {
  for_each         = local.apps
  length           = 32
  special          = true
  override_special = "!@#$%^&*()-_+="
}

resource "mysql_database" "app" {
  for_each = local.apps
  name     = each.value.database
}

resource "mysql_user" "app" {
  for_each           = local.apps
  user               = each.key
  host               = "%"
  plaintext_password = random_password.app[each.key].result
  tls_option         = "SSL"
}

resource "mysql_grant" "app" {
  for_each   = local.apps
  user       = mysql_user.app[each.key].user
  host       = mysql_user.app[each.key].host
  database   = mysql_database.app[each.key].name
  privileges = ["ALL"]
}

# Per-app secret shells are owned by firebase-cloud (modules/app-with-mysql).
# Read them as data sources and write versions populated with the values
# generated above.
data "google_secret_manager_secret" "app_user" {
  for_each  = local.apps
  secret_id = "${each.key}-db-user"
}

data "google_secret_manager_secret" "app_pass" {
  for_each  = local.apps
  secret_id = "${each.key}-db-pass"
}

data "google_secret_manager_secret" "app_name" {
  for_each  = local.apps
  secret_id = "${each.key}-db-name"
}

resource "google_secret_manager_secret_version" "app_user" {
  for_each    = local.apps
  secret      = data.google_secret_manager_secret.app_user[each.key].id
  secret_data = each.key
}

resource "google_secret_manager_secret_version" "app_pass" {
  for_each    = local.apps
  secret      = data.google_secret_manager_secret.app_pass[each.key].id
  secret_data = random_password.app[each.key].result
}

resource "google_secret_manager_secret_version" "app_name" {
  for_each    = local.apps
  secret      = data.google_secret_manager_secret.app_name[each.key].id
  secret_data = each.value.database
}
