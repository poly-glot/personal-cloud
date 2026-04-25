# Custom backup policy with no schedules — explicitly opts a volume out of
# scheduled backups. Reference this from any oci_core_volume_backup_policy_assignment
# (or the OCI console) to override the default-bronze auto-attachment that some
# OCI quickstarts do.
#
# Background: previous OKE node generations had the predefined `bronze` policy
# attached (probably via console or an earlier setup), producing 18 orphan
# monthly snapshots that cost ~\$1.70/month in incremental backup storage. The
# orphan snapshots were deleted out-of-band on 2026-04-25 and current boot
# volumes have no policy assignment. This resource exists so that re-attachment
# is opt-IN (assign this no-schedules policy) rather than opt-OUT.

resource "oci_core_volume_backup_policy" "no_schedules" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.project}-no-backup"
  # schedules block omitted = empty schedule list = no auto backups created
}
