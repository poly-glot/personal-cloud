# Network Security Group for MySQL NLB — exposes MySQL publicly on 3306
resource "oci_core_network_security_group" "mysql_nlb_nsg" {
  compartment_id = var.compartment_ocid
  vcn_id         = data.oci_core_subnet.private_subnet.vcn_id
  display_name   = "${var.project}-mysql-nlb-nsg"
}

resource "oci_core_network_security_group_security_rule" "mysql_nlb_ingress_3306" {
  network_security_group_id = oci_core_network_security_group.mysql_nlb_nsg.id
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

resource "oci_core_network_security_group_security_rule" "mysql_nlb_ingress_33060" {
  network_security_group_id = oci_core_network_security_group.mysql_nlb_nsg.id
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

resource "oci_core_network_security_group_security_rule" "mysql_nlb_egress_all" {
  network_security_group_id = oci_core_network_security_group.mysql_nlb_nsg.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  stateless                 = false
}

# Public NLB fronting MySQL HeatWave
resource "oci_network_load_balancer_network_load_balancer" "mysql_nlb" {
  compartment_id             = var.compartment_ocid
  display_name               = "${var.project}-mysql-nlb"
  subnet_id                  = data.oci_core_subnets.vcn_public_subnet.subnets[0].id
  is_private                 = false
  network_security_group_ids = [oci_core_network_security_group.mysql_nlb_nsg.id]
}

resource "oci_network_load_balancer_backend_set" "mysql_backend_set" {
  name                     = "${var.project}-mysql-backend-set"
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.mysql_nlb.id
  policy                   = "FIVE_TUPLE"
  is_preserve_source       = false

  health_checker {
    protocol = "TCP"
    port     = 3306
  }
}

resource "oci_network_load_balancer_backend" "mysql_backend" {
  backend_set_name         = oci_network_load_balancer_backend_set.mysql_backend_set.name
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.mysql_nlb.id
  port                     = 3306
  ip_address               = oci_mysql_mysql_db_system.mysql_heatwave.ip_address
}

resource "oci_network_load_balancer_listener" "mysql_listener" {
  default_backend_set_name = oci_network_load_balancer_backend_set.mysql_backend_set.name
  name                     = "${var.project}-mysql-listener"
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.mysql_nlb.id
  port                     = 3306
  protocol                 = "TCP"
}

resource "oci_network_load_balancer_backend_set" "mysql_x_backend_set" {
  name                     = "${var.project}-mysql-x-backend-set"
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.mysql_nlb.id
  policy                   = "FIVE_TUPLE"
  is_preserve_source       = false

  health_checker {
    protocol = "TCP"
    port     = 33060
  }
}

resource "oci_network_load_balancer_backend" "mysql_x_backend" {
  backend_set_name         = oci_network_load_balancer_backend_set.mysql_x_backend_set.name
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.mysql_nlb.id
  port                     = 33060
  ip_address               = oci_mysql_mysql_db_system.mysql_heatwave.ip_address
}

resource "oci_network_load_balancer_listener" "mysql_x_listener" {
  default_backend_set_name = oci_network_load_balancer_backend_set.mysql_x_backend_set.name
  name                     = "${var.project}-mysql-x-listener"
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.mysql_nlb.id
  port                     = 33060
  protocol                 = "TCP"
}