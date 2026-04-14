# Get the private subnet for MySQL HeatWave
data "oci_core_subnets" "vcn_private_subnet" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.project}-private-subnet"
}

# Get the public subnet for the MySQL NLB
data "oci_core_subnets" "vcn_public_subnet" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.project}-public-subnet"
}

# Get the VCN id (via the private subnet)
data "oci_core_subnet" "private_subnet" {
  subnet_id = data.oci_core_subnets.vcn_private_subnet.subnets[0].id
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
