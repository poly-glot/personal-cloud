output "mysql_host" {
  description = "MySQL HeatWave private IP address"
  value       = oci_mysql_mysql_db_system.mysql_heatwave.ip_address
}

output "mysql_port" {
  description = "MySQL port"
  value       = oci_mysql_mysql_db_system.mysql_heatwave.port
}

output "mysql_port_x" {
  description = "MySQL X Protocol port"
  value       = oci_mysql_mysql_db_system.mysql_heatwave.port_x
}

output "mysql_endpoint" {
  description = "MySQL connection endpoint"
  value       = "${oci_mysql_mysql_db_system.mysql_heatwave.ip_address}:${oci_mysql_mysql_db_system.mysql_heatwave.port}"
}

output "mysql_id" {
  description = "MySQL DB System OCID"
  value       = oci_mysql_mysql_db_system.mysql_heatwave.id
}

output "mysql_state" {
  description = "MySQL DB System state"
  value       = oci_mysql_mysql_db_system.mysql_heatwave.state
}

output "mysql_public_ip" {
  description = "Public IP of the shared NLB (junaid-nlb) fronting MySQL"
  value       = local.shared_nlb_public_ip
}

output "mysql_public_endpoint" {
  description = "Public MySQL connection endpoint (via shared NLB)"
  value       = "${local.shared_nlb_public_ip}:3306"
}
