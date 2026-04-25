# MySQL listeners + backends share the public NLB owned by 03-network-loadbalancer
# to stay within the Always Free quota (1 NLB). 03 owns the NLB resource and the
# shared NSG; 05 looks both up by display name and adds:
#   - NSG ingress rules for 3306 + 33060 (the MySQL classic + X protocol ports)
#   - Backend sets / backends / listeners on the shared NLB pointing at the
#     MySQL HeatWave DB system's private IP

data "oci_network_load_balancer_network_load_balancers" "shared" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.project}-nlb"
  state          = "ACTIVE"
}

data "oci_core_network_security_groups" "shared_nlb" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.project}-nlb-shared-nsg"
}

locals {
  shared_nlb_id        = data.oci_network_load_balancer_network_load_balancers.shared.network_load_balancer_collection[0].items[0].id
  shared_nlb_public_ip = [for ip in data.oci_network_load_balancer_network_load_balancers.shared.network_load_balancer_collection[0].items[0].ip_addresses : ip.ip_address if ip.is_public][0]
  shared_nsg_id        = data.oci_core_network_security_groups.shared_nlb.network_security_groups[0].id
}

resource "oci_core_network_security_group_security_rule" "shared_ingress_3306" {
  network_security_group_id = local.shared_nsg_id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  stateless                 = false

  tcp_options {
    destination_port_range {
      min = 3306
      max = 3306
    }
  }
}

resource "oci_core_network_security_group_security_rule" "shared_ingress_33060" {
  network_security_group_id = local.shared_nsg_id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  stateless                 = false

  tcp_options {
    destination_port_range {
      min = 33060
      max = 33060
    }
  }
}

resource "oci_network_load_balancer_backend_set" "mysql_backend_set" {
  name                     = "${var.project}-mysql-backend-set"
  network_load_balancer_id = local.shared_nlb_id
  policy                   = "FIVE_TUPLE"
  is_preserve_source       = false

  health_checker {
    protocol = "TCP"
    port     = 3306
  }
}

resource "oci_network_load_balancer_backend" "mysql_backend" {
  backend_set_name         = oci_network_load_balancer_backend_set.mysql_backend_set.name
  network_load_balancer_id = local.shared_nlb_id
  port                     = 3306
  ip_address               = oci_mysql_mysql_db_system.mysql_heatwave.ip_address
}

resource "oci_network_load_balancer_listener" "mysql_listener" {
  default_backend_set_name = oci_network_load_balancer_backend_set.mysql_backend_set.name
  name                     = "${var.project}-mysql-listener"
  network_load_balancer_id = local.shared_nlb_id
  port                     = 3306
  protocol                 = "TCP"
}

resource "oci_network_load_balancer_backend_set" "mysql_x_backend_set" {
  name                     = "${var.project}-mysql-x-backend-set"
  network_load_balancer_id = local.shared_nlb_id
  policy                   = "FIVE_TUPLE"
  is_preserve_source       = false

  health_checker {
    protocol = "TCP"
    port     = 33060
  }
}

resource "oci_network_load_balancer_backend" "mysql_x_backend" {
  backend_set_name         = oci_network_load_balancer_backend_set.mysql_x_backend_set.name
  network_load_balancer_id = local.shared_nlb_id
  port                     = 33060
  ip_address               = oci_mysql_mysql_db_system.mysql_heatwave.ip_address
}

resource "oci_network_load_balancer_listener" "mysql_x_listener" {
  default_backend_set_name = oci_network_load_balancer_backend_set.mysql_x_backend_set.name
  name                     = "${var.project}-mysql-x-listener"
  network_load_balancer_id = local.shared_nlb_id
  port                     = 33060
  protocol                 = "TCP"
}
