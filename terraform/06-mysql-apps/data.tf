data "oci_network_load_balancer_network_load_balancers" "mysql_nlb" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.project}-mysql-nlb"
  state          = "ACTIVE"
}

locals {
  mysql_nlb = data.oci_network_load_balancer_network_load_balancers.mysql_nlb.network_load_balancer_collection[0].items[0]
  mysql_host = [
    for ip in local.mysql_nlb.ip_addresses : ip.ip_address
    if ip.is_public
  ][0]
}

# Apps catalog published by firebase-cloud terraform (mysql-catalog.tf).
# Schema: { "<app>": { "database": "<db_name>", "sa_email": "<runtime sa email>" } }
data "google_secret_manager_secret_version" "mysql_app_catalog" {
  secret = "mysql-app-catalog"
}

locals {
  apps = jsondecode(data.google_secret_manager_secret_version.mysql_app_catalog.secret_data)
}
