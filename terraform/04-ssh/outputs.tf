output "connection_details" {
  value = [
    for session in oci_bastion_session.bastion_session :
    session.ssh_metadata.command
  ]
}
