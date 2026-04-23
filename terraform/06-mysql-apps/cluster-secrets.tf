resource "google_secret_manager_secret" "db_host" {
  secret_id = "db-host"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_host" {
  secret      = google_secret_manager_secret.db_host.id
  secret_data = local.mysql_host
}

resource "google_secret_manager_secret" "db_admin_user" {
  secret_id = "db-admin-user"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_admin_user" {
  secret      = google_secret_manager_secret.db_admin_user.id
  secret_data = var.mysql_admin_username
}

resource "google_secret_manager_secret" "db_admin_pass" {
  secret_id = "db-admin-pass"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_admin_pass" {
  secret      = google_secret_manager_secret.db_admin_pass.id
  secret_data = var.mysql_admin_password
}
