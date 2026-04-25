variable "project" {
  type        = string
  description = "Project name, matches the prefix used by the 05-mysql-heatwave stack"
}

variable "region" {
  type        = string
  description = "OCI region"
}

variable "compartment_ocid" {
  type        = string
  description = "OCI compartment containing the MySQL HeatWave NLB"
}

variable "gcp_project" {
  type        = string
  description = "GCP project hosting the Secret Manager secrets"
  default     = "firebase-cloud-491613"
}

variable "mysql_admin_username" {
  type        = string
  description = "MySQL HeatWave admin username (also written to db-admin-user in GSM)"
}

variable "mysql_admin_password" {
  type        = string
  description = "MySQL HeatWave admin password (also written to db-admin-pass in GSM)"
  sensitive   = true
}

