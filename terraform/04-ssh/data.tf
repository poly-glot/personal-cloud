data "oci_core_subnets" "vcn_private_subnet" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.project}-private-subnet"
}

data "oci_containerengine_clusters" "k8s_cluster" {
  compartment_id = var.compartment_ocid
  name           = "${var.project}-cluster"
}
