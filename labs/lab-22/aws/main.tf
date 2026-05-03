# ===========================================================================
# Lab22 — Refactorización Avanzada de S3 (De Monolítico a Modular)
# ===========================================================================
# Dos instancias del módulo s3-bucket:
#   - logs: bucket para almacenar logs de la aplicación
#   - data: bucket para datos críticos del negocio
# Cada instancia recibe etiquetas globales del proyecto combinadas con
# etiquetas específicas de su propósito mediante merge().
# ===========================================================================

# --- Data Sources ---

data "aws_caller_identity" "current" {}

# --- Locals ---

locals {
  account_id = data.aws_caller_identity.current.account_id

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
  force_destroy     = false

  tags = merge(local.common_tags, {
    Purpose            = "data"
    DataClassification = "confidential"
  })
}
