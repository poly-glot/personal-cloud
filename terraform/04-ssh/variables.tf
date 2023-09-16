variable "project" {
  type        = string
  description = "Project name"
}

variable "compartment_ocid" {
  type        = string
  description = "The compartment to create the resources in"
}

variable "region" {
  type        = string
  description = "The region to provision the resources in"
}

variable "ssh_public_key" {
  type        = string
  description = "The SSH public key to use for connecting to the worker nodes"
}

variable "client_cidr_block_allow_list" {
  type        = list(string)
  description = "IP whitelisting"
}

variable "instance_ids" {
  type = list(string)
}
