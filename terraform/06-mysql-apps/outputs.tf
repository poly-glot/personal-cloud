output "provisioned_apps" {
  description = "Apps provisioned by this stack — logged for audit after apply"
  value = [
    for app, cfg in local.apps : {
      app             = app
      database        = cfg.database
      service_account = cfg.sa_email
    }
  ]
}

output "mysql_host" {
  description = "Public MySQL NLB IP stored in the db-host GSM secret"
  value       = local.mysql_host
}
