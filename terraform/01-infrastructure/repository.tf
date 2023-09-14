resource "oci_artifacts_container_repository" "docker_repository" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.project}-repository"

  is_immutable = false
  is_public    = false
}
