data "oci_core_subnets" "vcn_public_subnet" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.project}-public-subnet"
}

# Get the node pool to discover nodes dynamically
data "oci_containerengine_node_pools" "node_pools" {
  compartment_id = var.compartment_ocid
  name           = "${var.project}-node-pool"
}

# Get the nodes in the node pool
data "oci_containerengine_node_pool" "main_node_pool" {
  node_pool_id = data.oci_containerengine_node_pools.node_pools.node_pools[0].id
}

locals {
  # Get the first active node from the node pool as the main node
  active_nodes = [
    for node in data.oci_containerengine_node_pool.main_node_pool.nodes :
    node if node.state == "ACTIVE"
  ]
  main_node_id = length(local.active_nodes) > 0 ? local.active_nodes[0].id : null
}
