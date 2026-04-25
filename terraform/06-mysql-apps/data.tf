data "oci_network_load_balancer_network_load_balancers" "shared_nlb" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.project}-nlb"
  state          = "ACTIVE"
}

locals {
  shared_nlb = data.oci_network_load_balancer_network_load_balancers.shared_nlb.network_load_balancer_collection[0].items[0]
  mysql_host = [
    for ip in local.shared_nlb.ip_addresses : ip.ip_address
    if ip.is_public
  ][0]
}

# Apps catalog published by firebase-cloud terraform (mysql-catalog.tf).
# Schema: { "<app>": { "database": "<db_name>", "sa_email": "<runtime sa email>" } }
data "google_secret_manager_secret_version" "mysql_app_catalog" {
  secret = "mysql-app-catalog"
}

locals {
  # nonsensitive: GSM data is sensitive by default, but the catalog only
  # contains app names + DB names + SA emails — non-secret config that we
  # need to use in for_each and surface in outputs.
  apps = nonsensitive(jsondecode(data.google_secret_manager_secret_version.mysql_app_catalog.secret_data))
}
