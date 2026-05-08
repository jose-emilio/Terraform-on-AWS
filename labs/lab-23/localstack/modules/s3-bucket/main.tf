# ===========================================================================
# Módulo s3-bucket — Versión LocalStack
# ===========================================================================
# Igual que la version AWS pero sin prevent_destroy para facilitar la
# limpieza en entorno local. El bloqueo de acceso público no se incluye
# porque LocalStack Community no lo emula completamente.

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
}

# --- Versiónado ---

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}
