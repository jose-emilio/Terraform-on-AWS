# Bootstrap del lab-40 — roles IAM que simulan tres cuentas distintas
#
# Este sub-proyecto crea TRES roles IAM dentro de tu cuenta AWS actual,
# uno por cada "cuenta simulada" del lab principal:
#
#   lab40-core-admin  → simula la cuenta "core" (us-east-1)
#   lab40-eu-admin    → simula la cuenta "prod-eu" (eu-west-3)
#   lab40-jp-admin    → simula la cuenta "prod-jp" (ap-northeast-1)
#
# El lab principal asume estos roles en cada provider con bloques
# `assume_role { ... }`. En un escenario real con múltiples cuentas
# AWS, los role_arn apuntarían a OTRAS cuentas (no a la tuya) y la
# Trust Policy permitiría AssumeRole cross-account. La simulación de
# este lab usa la misma cuenta para que sea ejecutable con un solo
# perfil AWS, pero el patrón Terraform es idéntico al multi-cuenta real.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

# ── Trust Policy: permite que el caller actual (tu usuario/rol) asuma estos roles
data "aws_iam_policy_document" "assume_self" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.arn]
    }
  }
}

locals {
  simulated_accounts = ["core", "eu", "jp"]
}

resource "aws_iam_role" "simulated_account" {
  for_each = toset(local.simulated_accounts)

  name               = "lab40-${each.value}-admin"
  assume_role_policy = data.aws_iam_policy_document.assume_self.json

  tags = {
    Name    = "lab40-${each.value}-admin"
    Project = "lab40"
  }
}

# Permisos administrativos sobre la cuenta — equivalente al rol de admin que
# tendrías en una cuenta real dedicada. En producción NUNCA uses
# AdministratorAccess; restringe la policy al mínimo necesario.
resource "aws_iam_role_policy_attachment" "admin" {
  for_each = aws_iam_role.simulated_account

  role       = each.value.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "account_id" {
  description = "Account ID donde se han creado los roles (la usarás como var.account_id en el lab)"
  value       = data.aws_caller_identity.current.account_id
}

output "role_arns" {
  description = "ARN de cada rol simulado, indexado por cuenta"
  value       = { for k, v in aws_iam_role.simulated_account : k => v.arn }
}

output "next_step" {
  description = "Comando para preparar las variables del lab principal"
  value       = <<-EOT

    # Exporta el Account ID y vuelve al directorio del lab principal:
    export ACCOUNT_ID=${data.aws_caller_identity.current.account_id}
    cd ..
    terraform init -backend-config=aws.s3.tfbackend \
                   -backend-config="bucket=terraform-state-labs-$${ACCOUNT_ID}"
    terraform apply -var "account_id=$${ACCOUNT_ID}"
  EOT
}
