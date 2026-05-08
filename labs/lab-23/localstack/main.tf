# ===========================================================================
# Lab22 — Refactorización Avanzada de S3 (De Monolítico a Modular)
# ===========================================================================
# Version LocalStack: usa account_id fijo ya que skip_requesting_account_id = true
# ===========================================================================

# --- Locals ---

locals {
  account_id = "000000000000"

  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Project     = var.project_name
  }
}

# ===========================================================================
# Módulo S3 — Bucket de Logs
# ===========================================================================

module "logs_bucket" {
  source = "./modules/s3-bucket"

  bucket_name       = "${var.project_name}-logs-${local.account_id}"
  enable_versioning = false
  force_destroy     = true

  tags = merge(local.common_tags, {
    Purpose            = "logs"
    DataClassification = "internal"
  })
}

# ===========================================================================
# Módulo S3 — Bucket de Datos
# ===========================================================================

module "data_bucket" {
  source = "./modules/s3-bucket"

  bucket_name       = "${var.project_name}-data-${local.account_id}"
  enable_versioning = true
  # En la version aws/, force_destroy = false para proteger datos criticos.
  # En LocalStack lo dejamos en true para facilitar la limpieza local —
  # no hay datos reales que proteger en esta emulacion.
  force_destroy = true

  tags = merge(local.common_tags, {
    Purpose            = "data"
    DataClassification = "confidential"
  })
}
