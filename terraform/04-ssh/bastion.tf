resource "oci_bastion_bastion" "bastion" {
  bastion_type                 = "STANDARD"
  compartment_id               = var.compartment_ocid
  target_subnet_id             = data.oci_core_subnets.vcn_private_subnet.subnets[0].id
  client_cidr_block_allow_list = var.client_cidr_block_allow_list
  name                         = "${var.project}-bastion"
  max_session_ttl_in_seconds   = 10800
}

resource "oci_bastion_session" "bastion_session" {
  count = length(var.instance_ids)

  bastion_id = oci_bastion_bastion.bastion.id

  key_details {
    public_key_content = var.ssh_public_key
  }

  target_resource_details {
    session_type                               = "MANAGED_SSH"
    target_resource_id                         = var.instance_ids[count.index]
    target_resource_operating_system_user_name = "opc"
    target_resource_port                       = "22"
  }

  session_ttl_in_seconds = 3600

  display_name = "${var.project}-bastion-private-host-${count.index}"
}
