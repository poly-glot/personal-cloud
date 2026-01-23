resource "oci_network_load_balancer_network_load_balancer" "nlb" {
  compartment_id                 = var.compartment_ocid
  display_name                   = "${var.project}-nlb"
  subnet_id                      = data.oci_core_subnets.vcn_public_subnet.subnets[0].id
  is_private                     = false
  is_preserve_source_destination = false
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
