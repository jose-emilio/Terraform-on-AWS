# --- VPC ---

output "vpc_id" {
  description = "ID de la VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR de la VPC"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "IDs de las subredes privadas"
  value       = module.vpc.private_subnets
}

output "database_subnet_ids" {
  description = "IDs de las subredes de base de datos"
  value       = module.vpc.database_subnets
}

output "database_subnet_group_name" {
  description = "Nombre del grupo de subredes de base de datos"
  value       = module.vpc.database_subnet_group_name
}

# --- RDS ---

output "db_instance_id" {
  description = "ID de la instancia RDS"
  value       = module.rds.db_instance_identifier
}

output "db_instance_endpoint" {
  description = "Endpoint de conexión de la instancia RDS"
  value       = module.rds.db_instance_endpoint
}

output "db_instance_port" {
  description = "Puerto de la instancia RDS"
  value       = module.rds.db_instance_port
}

output "db_instance_name" {
  description = "Nombre de la base de datos"
  value       = module.rds.db_instance_name
}

output "db_master_user_secret_arn" {
  description = "ARN del secreto en Secrets Manager con la contraseña generada por RDS"
  value       = module.rds.db_instance_master_user_secret_arn
}

# --- Seguridad (verificación de compliance) ---
# Estos outputs reflejan el CONTRATO del wrapper: los flags están
# hardcoded a `true` en el bloque `module "rds"` de main.tf, así que el
# valor `true` es cierto por construcción mientras el módulo no se
# modifique. La fuente de verdad real es el código del módulo (busca
# `storage_encrypted` y `deletion_protection` en main.tf).
#
# El módulo `terraform-aws-modules/rds/aws` v6.x NO expone estos campos
# como outputs, así que no podemos hacer `module.rds.db_instance_<flag>`.
# Para auditar el estado real desde fuera de Terraform usa AWS CLI:
#   aws rds describe-db-instances --db-instance-identifier <id> \
#     --query 'DBInstances[0].{StorageEncrypted: StorageEncrypted, DeletionProtection: DeletionProtection}'
# (La sección 3.2 del README muestra este comando.)

output "db_storage_encrypted" {
  description = "Confirmación de que el almacenamiento RDS está cifrado en reposo (true por contrato del wrapper)"
  value       = true
}

output "db_deletion_protection" {
  description = "Confirmación de que la protección contra borrado está activa (true por contrato del wrapper)"
  value       = true
}

output "security_group_id" {
  description = "ID del security group de RDS"
  value       = aws_security_group.rds.id
}
