# MySQL HeatWave Free Tier Database System
resource "oci_mysql_mysql_db_system" "mysql_heatwave" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.project}-mysql"

  # Free Tier shape
  shape_name          = "MySQL.Free"
  configuration_id    = data.oci_mysql_mysql_configurations.free_tier.configurations[0].id
  # Use AD-2 which has MySQL Free tier available
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[1].name

  # Network - place in private subnet (same as K8s nodes)
  subnet_id = data.oci_core_subnets.vcn_private_subnet.subnets[0].id

  # Admin credentials
  admin_username = var.mysql_admin_username
  admin_password = var.mysql_admin_password

  # Storage - 50GB included in Free Tier
  data_storage_size_in_gb = 50

  # Note: Backup policy not supported for Always Free DB systems

  description = "MySQL HeatWave Free Tier for ${var.project}"

  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = false  # Set to true in production
  }
}
