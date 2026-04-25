# Shared NSG attached to the public NLB. 03 declares the NSG and adds rules
# for OKE traffic (HTTP/HTTPS); 05-mysql-heatwave appends MySQL ingress rules
# (3306/33060) so a single NLB can front both OKE and MySQL.
resource "oci_core_network_security_group" "nlb_shared" {
  compartment_id = var.compartment_ocid
  vcn_id         = data.oci_core_subnets.vcn_public_subnet.subnets[0].vcn_id
  display_name   = "${var.project}-nlb-shared-nsg"
}

resource "oci_core_network_security_group_security_rule" "nlb_shared_ingress_http" {
  network_security_group_id = oci_core_network_security_group.nlb_shared.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  stateless                 = false

  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nlb_shared_ingress_https" {
  network_security_group_id = oci_core_network_security_group.nlb_shared.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  stateless                 = false

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nlb_shared_egress_all" {
  network_security_group_id = oci_core_network_security_group.nlb_shared.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  stateless                 = false
}

resource "oci_network_load_balancer_network_load_balancer" "nlb" {
  compartment_id                 = var.compartment_ocid
  display_name                   = "${var.project}-nlb"
  subnet_id                      = data.oci_core_subnets.vcn_public_subnet.subnets[0].id
  is_private                     = false
  is_preserve_source_destination = false
  network_security_group_ids     = [oci_core_network_security_group.nlb_shared.id]
}

resource "oci_network_load_balancer_backend_set" "backend_set" {
  health_checker {
    protocol = "TCP"
    port     = 32080
  }
  name                     = "${var.project}-backend-set"
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.nlb.id
  policy                   = "FIVE_TUPLE"
  is_preserve_source       = false
}

resource "oci_network_load_balancer_backend" "nlb_backend_http" {
  backend_set_name         = oci_network_load_balancer_backend_set.backend_set.name
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.nlb.id
  port                     = 32080
  target_id                = local.main_node_id
}

resource "oci_network_load_balancer_listener" "nlb_listener_http" {
  default_backend_set_name = oci_network_load_balancer_backend_set.backend_set.name
  name                     = "${var.project}-nlb-listener-http"
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.nlb.id
  port                     = "80"
  protocol                 = "TCP"
}

resource "oci_network_load_balancer_backend_set" "backend_set_https" {
  health_checker {
    protocol = "TCP"
    port     = 32443
  }
  name                     = "${var.project}-backend-set-https"
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.nlb.id
  policy                   = "FIVE_TUPLE"
  is_preserve_source       = false
}

resource "oci_network_load_balancer_backend" "nlb_backend_https" {
  backend_set_name         = oci_network_load_balancer_backend_set.backend_set_https.name
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.nlb.id
  port                     = 32443
  target_id                = local.main_node_id
}

resource "oci_network_load_balancer_listener" "nlb_listener_https" {
  default_backend_set_name = oci_network_load_balancer_backend_set.backend_set_https.name
  name                     = "${var.project}-nlb-listener-https"
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.nlb.id
  port                     = "443"
  protocol                 = "TCP"
}
