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

variable "mysql_admin_username" {
  type        = string
  description = "MySQL admin username"
  default     = "admin"
}

variable "mysql_admin_password" {
  type        = string
  description = "MySQL admin password"
  sensitive   = true
}
