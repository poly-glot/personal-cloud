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

variable "main_instance_ocid" {
  type        = string
  description = "Instance OCID in node pool where traefik is deployed"
}
