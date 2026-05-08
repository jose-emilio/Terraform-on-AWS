terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Configuración parcial del backend. Todos los parámetros están en
  # aws.s3.tfbackend. Inicia el lab con:
  #   terraform init -backend-config=aws.s3.tfbackend \
  #                  -backend-config="bucket=terraform-state-labs-<ACCOUNT_ID>"
  backend "s3" {}
}

# ══════════════════════════════════════════════════════════════════════════════
# Tres providers AWS — uno por cada "cuenta simulada"
# ══════════════════════════════════════════════════════════════════════════════
#
# Cada bloque `provider "aws"` es una instancia independiente del provider con:
#   - su propio alias (identifica el provider en los recursos)
#   - su propia región
#   - su propio rol IAM asumido (simula la cuenta)
#
# El bloque `assume_role { ... }` hace que Terraform invoque sts:AssumeRole
# antes de cada llamada API. En multi-cuenta REAL, role_arn apuntaría a
# OTRA cuenta AWS y la cuenta llamante necesitaría permisos sts:AssumeRole
# cross-account. En este lab los tres roles viven en la misma cuenta para
# poder ejecutar el lab con un solo perfil AWS — el patrón Terraform es
# idéntico al multi-cuenta real.
#
# Los roles se crean en bootstrap/ ANTES de aplicar este lab.

# ── aws.core — cuenta "core" simulada (us-east-1) ───────────────────────────
# Hospeda los recursos compartidos cross-region:
#   - KMS multi-region primary key
#   - Hosted zone privada Route53 con los registros regionales
#   - VPC mínima (necesaria para asociar la zona privada)
provider "aws" {
  alias  = "core"
  region = "us-east-1"

  assume_role {
    role_arn     = "arn:aws:iam::${var.account_id}:role/lab40-core-admin"
    session_name = "lab40-core-session"
  }
}

# ── aws.eu — cuenta "prod-eu" simulada (eu-west-3, París) ───────────────────
provider "aws" {
  alias  = "eu"
  region = "eu-west-3"

  assume_role {
    role_arn     = "arn:aws:iam::${var.account_id}:role/lab40-eu-admin"
    session_name = "lab40-eu-session"
  }
}

# ── aws.jp — cuenta "prod-jp" simulada (ap-northeast-1, Tokio) ──────────────
provider "aws" {
  alias  = "jp"
  region = "ap-northeast-1"

  assume_role {
    role_arn     = "arn:aws:iam::${var.account_id}:role/lab40-jp-admin"
    session_name = "lab40-jp-session"
  }
}

# Nota importante: NO existe provider "aws" sin alias. Eso significa que
# TODOS los recursos del root y todas las llamadas a módulos deben declarar
# explícitamente el provider que usan (mediante `provider = aws.<alias>`
# en recursos directos o `providers = { ... }` en módulos). Un recurso que
# omita esa declaración fallará con `No default provider configured`.
