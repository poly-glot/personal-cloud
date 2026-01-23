output "nlb_ip" {
  value = oci_network_load_balancer_network_load_balancer.nlb.ip_addresses
}

output "main_node_id" {
  description = "The OCID of the main node used for NLB backend"
  value       = local.main_node_id
}

output "main_node_name" {
  description = "The name of the main node used for NLB backend"
  value       = length(local.active_nodes) > 0 ? local.active_nodes[0].name : "No active nodes found"
}
