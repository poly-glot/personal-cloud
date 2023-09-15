data "oci_core_subnets" "vcn_public_subnet" {
  compartment_id = var.compartment_id
  display_name   = "${var.project}-public-subnet"
}
