output "region" {
  description = "Región AWS donde se desplegó esta instancia del módulo"
  value       = data.aws_region.this.region
}

output "bucket_name" {
  description = "Nombre del bucket S3 regional"
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "ARN del bucket S3 regional"
  value       = aws_s3_bucket.this.arn
}

output "kms_replica_arn" {
  description = "ARN de la KMS replica key de esta región"
  value       = aws_kms_replica_key.this.arn
}

output "kms_alias_name" {
  description = "Alias de la KMS replica key (formato 'alias/<project>-<region_short>')"
  value       = aws_kms_alias.this.name
}

output "ssm_parameter_name" {
  description = "Nombre del parámetro SSM con la región activa"
  value       = aws_ssm_parameter.active_region.name
}

output "regional_dns_name" {
  description = "FQDN regional registrado en la zona privada compartida"
  value       = aws_route53_record.regional_endpoint.fqdn
}
