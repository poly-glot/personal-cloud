provider "oci" {
  region = var.region
}

provider "google" {
  project = var.gcp_project
}

provider "mysql" {
  endpoint = "${local.mysql_host}:3306"
  username = var.mysql_admin_username
  password = var.mysql_admin_password
  # skip-verify: connection is TLS-encrypted, but the OCI MySQL certificate
  # doesn't list the NLB public IP as a SAN, so full verification fails.
  tls = "skip-verify"
}
