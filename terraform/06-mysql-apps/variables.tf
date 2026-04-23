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

variable "apps" {
  type = map(object({
    database        = string
    service_account = string
  }))
  description = "Apps sharing the MySQL HeatWave cluster. Map key = MySQL username and GSM secret prefix."
  default = {
    shehryar = {
      database        = "rn_chatapp"
      service_account = "shehryar-run@firebase-cloud-491613.iam.gserviceaccount.com"
    }
  }
}
