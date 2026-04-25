resource "oci_containerengine_cluster" "k8s_cluster" {
  compartment_id     = var.compartment_ocid
  kubernetes_version = "v1.34.2"
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

data "oci_containerengine_node_pool_option" "oke_options" {
  # "all" returns sources for all supported k8s versions across the tenancy
  node_pool_option_id = "all"
  compartment_id      = var.compartment_ocid
}

locals {
  # OKE source-name pattern: "Oracle-Linux-<os-ver>-aarch64-<date>-OKE-<k8s-ver>-<build>"
  # Pick the newest aarch64 source matching the cluster's k8s version.
  # OKE-specific node images aren't returned by oci_core_images (the Compute
  # platform-images API); they only appear via the OKE node-pool-options API.
  k8s_ver = replace(oci_containerengine_cluster.k8s_cluster.kubernetes_version, "v", "")
  oke_node_image = reverse(sort([
    for s in data.oci_containerengine_node_pool_option.oke_options.sources :
    s if can(regex("aarch64.*OKE-${local.k8s_ver}-", s.source_name))
  ]))[0]
}

resource "oci_containerengine_node_pool" "k8s_node_pool" {
  cluster_id         = oci_containerengine_cluster.k8s_cluster.id
  compartment_id     = var.compartment_ocid
  kubernetes_version = "v1.34.2"
  name               = "${var.project}-node-pool"
  node_config_details {
    dynamic "placement_configs" {
      for_each = local.azs
      content {
        availability_domain = placement_configs.value
        subnet_id           = oci_core_subnet.vcn_private_subnet.id
      }
    }
    size = 2
  }
  node_shape = "VM.Standard.A1.Flex"

  node_shape_config {
    memory_in_gbs = 12
    ocpus         = 2
  }

  node_source_details {
    image_id    = local.oke_node_image.image_id
    source_type = "image"
  }

  lifecycle {
    ignore_changes = [
      defined_tags,
      node_metadata,
      node_config_details[0].placement_configs,
      # node_source_details intentionally NOT ignored: when kubernetes_version
      # changes, the OKE image must change with it (OCI rejects node-pool
      # k8s version updates that don't match the bundled image version).
    ]
  }

  ssh_public_key = var.ssh_public_key
}

