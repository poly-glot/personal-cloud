resource "oci_containerengine_cluster" "k8s_cluster" {
  compartment_id     = var.compartment_ocid
  kubernetes_version = "v1.28.2"
  name               = "${var.project}-cluster"
  vcn_id             = module.vcn.vcn_id

  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = oci_core_subnet.vcn_public_subnet.id
  }

  options {
    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }
    kubernetes_network_config {
      pods_cidr     = "10.244.0.0/16"
      services_cidr = "10.96.0.0/16"
    }
    service_lb_subnet_ids = [oci_core_subnet.vcn_public_subnet.id]
  }
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

locals {
  azs = data.oci_identity_availability_domains.ads.availability_domains[*].name
}

data "oci_core_images" "latest_image" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  filter {
    name   = "display_name"
    values = ["^.*aarch64-.*$"]
    regex  = true
  }
}

resource "oci_containerengine_node_pool" "k8s_node_pool" {
  cluster_id         = oci_containerengine_cluster.k8s_cluster.id
  compartment_id     = var.compartment_ocid
  kubernetes_version = "v1.28.2"
  name               = "${var.project}-node-pool"
  node_config_details {
    dynamic "placement_configs" {
      for_each = local.azs
      content {
        availability_domain = placement_configs.value
        subnet_id           = oci_core_subnet.vcn_private_subnet.id
      }
    }
    size = 4
  }
  node_shape = "VM.Standard.A1.Flex"

  node_shape_config {
    memory_in_gbs = 6
    ocpus         = 1
  }

  node_source_details {
    image_id    = data.oci_core_images.latest_image.images.0.id
    source_type = "image"
  }

  lifecycle {
    ignore_changes = [
      kubernetes_version,
      defined_tags,
      node_metadata,
      node_config_details[0].placement_configs,
      node_source_details
    ]
  }

  ssh_public_key = var.ssh_public_key
}

