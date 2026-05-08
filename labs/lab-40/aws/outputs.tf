# ── Cuenta y recursos globales ───────────────────────────────────────────────
output "account_id" {
  description = "Account ID de la cuenta AWS donde residen los roles simulados"
  value       = data.aws_caller_identity.core.account_id
}

output "kms_primary_arn" {
  description = "ARN de la KMS multi-region primary key (en us-east-1)"
  value       = aws_kms_key.global_primary.arn
}

output "kms_primary_alias" {
  description = "Alias de la KMS primary"
  value       = aws_kms_alias.global_primary.name
}

output "private_zone_id" {
  description = "Zone ID de la hosted zone privada compartida"
  value       = aws_route53_zone.private.zone_id
}

output "private_zone_name" {
  description = "Nombre de la hosted zone privada"
  value       = aws_route53_zone.private.name
}

# ── Detalle por región (a través del módulo) ─────────────────────────────────
output "region_eu" {
  description = "Recursos desplegados por la instancia EU del módulo"
  value = {
    region             = module.app_eu.region
    bucket_name        = module.app_eu.bucket_name
    bucket_arn         = module.app_eu.bucket_arn
    kms_replica_arn    = module.app_eu.kms_replica_arn
    kms_alias_name     = module.app_eu.kms_alias_name
    ssm_parameter_name = module.app_eu.ssm_parameter_name
    regional_dns_name  = module.app_eu.regional_dns_name
  }
}

output "region_jp" {
  description = "Recursos desplegados por la instancia JP del módulo"
  value = {
    region             = module.app_jp.region
    bucket_name        = module.app_jp.bucket_name
    bucket_arn         = module.app_jp.bucket_arn
    kms_replica_arn    = module.app_jp.kms_replica_arn
    kms_alias_name     = module.app_jp.kms_alias_name
    ssm_parameter_name = module.app_jp.ssm_parameter_name
    regional_dns_name  = module.app_jp.regional_dns_name
  }
}

# ── Comandos de verificación rápida ──────────────────────────────────────────
output "verify_commands" {
  description = "Comandos AWS CLI para verificar el despliegue cross-region"
  value       = <<-EOT

    # ── Validar la KMS primary y sus replicas ────────────────────────────────
    aws kms describe-key --key-id ${aws_kms_alias.global_primary.name} \
      --region us-east-1 --query 'KeyMetadata.MultiRegionConfiguration'

    # ── Buckets S3 cifrados con replica KMS ──────────────────────────────────
    aws s3api get-bucket-encryption --bucket ${module.app_eu.bucket_name} \
      --region eu-west-3
    aws s3api get-bucket-encryption --bucket ${module.app_jp.bucket_name} \
      --region ap-northeast-1

    # ── Parámetros SSM regionales ────────────────────────────────────────────
    aws ssm get-parameter --name ${module.app_eu.ssm_parameter_name} \
      --region eu-west-3
    aws ssm get-parameter --name ${module.app_jp.ssm_parameter_name} \
      --region ap-northeast-1

    # ── Registros DNS de la zona privada ─────────────────────────────────────
    aws route53 list-resource-record-sets --hosted-zone-id ${aws_route53_zone.private.zone_id} \
      --query "ResourceRecordSets[?Type=='CNAME']"

  EOT
}
