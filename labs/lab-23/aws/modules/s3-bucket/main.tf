# ===========================================================================
# Módulo s3-bucket — Bucket S3 con buenas prácticas
# ===========================================================================
# Crea un bucket S3 con:
#   - Versionado configurable
#   - Bloqueo total de acceso público
#   - Protección contra destrucción accidental (lifecycle)
#   - Etiquetado combinado (merge de tags globales + específicas)

# --- Locals: combinación de etiquetas ---

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "s3-bucket"
  }

  effective_tags = merge(local.default_tags, var.tags)
}

# --- Bucket S3 ---

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.effective_tags, {
    Name = var.bucket_name
  })

  lifecycle {
    prevent_destroy = true
  }
}

# --- Versionado ---

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# --- Bloqueo de acceso público ---

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
