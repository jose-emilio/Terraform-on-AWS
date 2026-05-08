output "secret_arn" {
  # En la version aws/, este output apunta al ARN de aws_secretsmanager_secret.
  # Aqui apunta al ARN del aws_ssm_parameter SecureString porque LocalStack
  # Community emula Secrets Manager solo parcialmente. El nombre del output
  # se mantiene para que el Root Module sea identico en ambas variantes.
  description = "ARN del parámetro SSM SecureString con la contraseña (sustituto de Secrets Manager en LocalStack)"
  value       = aws_ssm_parameter.db_password.arn
}

output "config_summary" {
  description = "Resumen de la configuración de la base de datos (sin contraseña)"
  value = {
    engine         = var.db_config.engine
    engine_version = var.db_config.engine_version
    instance_class = var.db_config.instance_class
    port           = var.db_config.port
    multi_az       = var.db_config.multi_az
    storage_gb     = var.db_config.allocated_storage
    backup_days    = var.db_config.backup_retention_days
  }
}

output "ssm_prefix" {
  description = "Prefijo de los parámetros SSM creados"
  value       = "/${var.project_name}/db/"
}
