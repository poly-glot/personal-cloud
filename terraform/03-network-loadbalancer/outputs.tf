output "nlb_ip" {
  value = oci_network_load_balancer_network_load_balancer.nlb.ip_addresses
}

output "main_node_ip" {
  description = "Private IP of the main OKE node used as the NLB backend"
  value       = local.main_node_ip
}

output "main_node_name" {
  description = "The name of the main node used for NLB backend"
  value       = length(local.active_nodes) > 0 ? local.active_nodes[0].name : "No active nodes found"
}
