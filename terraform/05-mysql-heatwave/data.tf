# Get the private subnet for MySQL HeatWave
data "oci_core_subnets" "vcn_private_subnet" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.project}-private-subnet"
}

# Get availability domains
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

# Get MySQL configurations to find the Free tier shape
data "oci_mysql_mysql_configurations" "free_tier" {
  compartment_id = var.compartment_ocid
  shape_name     = "MySQL.Free"
  state          = "ACTIVE"
  type           = ["DEFAULT"]
}
