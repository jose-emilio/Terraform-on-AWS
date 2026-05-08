# Módulo `app-region`
#
# Crea la "pila regional" de la aplicación:
#   1. KMS replica key derivada de la primary (en aws.shared)
#   2. Bucket S3 cifrado con la replica KMS
#   3. Parámetro SSM con la región activa
#   4. Registro CNAME en la hosted zone privada compartida (aws.shared)
#
# Cada instancia del módulo se despliega en una región distinta (eu, jp...)
# pero comparte la KMS primary y la zona DNS — eso es lo que justifica
# `configuration_aliases` con DOS providers.

# ── Identidad de la región destino (aws.this) ───────────────────────────
data "aws_region" "this" {
  provider = aws.this
}

data "aws_caller_identity" "this" {
  provider = aws.this
}

locals {
  # Sufijo corto y estable para usar en nombres de recursos.
  # us-east-1 → useast1, eu-west-3 → euwest3, ap-northeast-1 → apnortheast1
  region_short = replace(data.aws_region.this.region, "-", "")
}

# ══════════════════════════════════════════════════════════════════════════════
# KMS REPLICA KEY — vive en aws.this, deriva de la primary en aws.shared
# ══════════════════════════════════════════════════════════════════════════════
#
# `aws_kms_replica_key` es un tipo especial de recurso: requiere un provider
# que apunte a la región DESTINO (aws.this) y un `primary_key_arn` que
# referencia la primary en otra región. AWS gestiona la replicación
# bidireccional del material criptográfico entre regiones.
resource "aws_kms_replica_key" "this" {
  provider = aws.this

  primary_key_arn         = var.primary_kms_arn
  description             = "Réplica regional de KMS multi-region en ${data.aws_region.this.region}"
  deletion_window_in_days = 7

  tags = merge(var.tags, {
    Name   = "${var.project}-kms-${local.region_short}"
    Region = data.aws_region.this.region
    Role   = "replica"
  })
}

resource "aws_kms_alias" "this" {
  provider = aws.this

  name          = "alias/${var.project}-${local.region_short}"
  target_key_id = aws_kms_replica_key.this.key_id
}

# ══════════════════════════════════════════════════════════════════════════════
# BUCKET S3 REGIONAL — cifrado con la replica KMS local
# ══════════════════════════════════════════════════════════════════════════════
resource "aws_s3_bucket" "this" {
  provider = aws.this

  bucket = "${var.project}-app-${data.aws_caller_identity.this.account_id}-${local.region_short}"

  tags = merge(var.tags, {
    Name   = "${var.project}-app-${local.region_short}"
    Region = data.aws_region.this.region
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  provider = aws.this
  bucket   = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_replica_key.this.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "this" {
  provider = aws.this
  bucket   = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  provider = aws.this
  bucket   = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ══════════════════════════════════════════════════════════════════════════════
# SSM PARAMETER — descubrimiento en runtime de la región activa
# ══════════════════════════════════════════════════════════════════════════════
resource "aws_ssm_parameter" "active_region" {
  provider = aws.this

  name        = "/${var.project}/${local.region_short}/active-region"
  type        = "String"
  value       = data.aws_region.this.region
  description = "Región activa para la pila ${local.region_short}"

  tags = merge(var.tags, {
    Region = data.aws_region.this.region
  })
}

# ══════════════════════════════════════════════════════════════════════════════
# REGISTRO CNAME EN LA ZONA DNS COMPARTIDA — vive en aws.shared
# ══════════════════════════════════════════════════════════════════════════════
#
# Aquí es donde `configuration_aliases` se gana su sitio: necesitamos crear
# un recurso en una región DIFERENTE (la de aws.shared) desde el mismo
# módulo. Sin `configuration_aliases`, este recurso tendría que vivir
# fuera del módulo, rompiendo la encapsulación.
resource "aws_route53_record" "regional_endpoint" {
  provider = aws.shared

  zone_id = var.private_zone_id
  name    = "${local.region_short}.${var.private_zone_name}"
  type    = "CNAME"
  ttl     = 60
  records = ["${aws_s3_bucket.this.bucket}.s3.${data.aws_region.this.region}.amazonaws.com"]
}
