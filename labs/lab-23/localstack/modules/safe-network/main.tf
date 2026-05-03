# ===========================================================================
# Módulo safe-network — VPC con postcondición RFC 1918 (LocalStack)
# ===========================================================================
# Diferencias con la version aws/:
#   - No usa `data "aws_availability_zones"`: en LocalStack Community la
#     emulacion del data source de AZs no siempre devuelve resultados
#     consistentes, asi que se itera sobre indices fijos (0, 1).
#   - Las subnets se crean SIN `availability_zone`: en AWS real ese campo
#     es requerido, pero LocalStack tolera la omision y asigna una AZ ficticia.
# La postcondicion RFC 1918 funciona identicamente porque la evalua el motor
# de Terraform, no el provider.

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "safe-network"
  }

  effective_tags = merge(local.default_tags, var.tags)
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.effective_tags, {
    Name = "vpc-${var.project_name}"
  })

  lifecycle {
    postcondition {
      condition = anytrue([
        can(regex("^10\\.", self.cidr_block)),
        can(regex("^172\\.(1[6-9]|2[0-9]|3[01])\\.", self.cidr_block)),
        can(regex("^192\\.168\\.", self.cidr_block)),
      ])
      error_message = "El CIDR ${self.cidr_block} no es un rango privado RFC 1918. Usa 10.0.0.0/8, 172.16.0.0/12, o 192.168.0.0/16."
    }
  }
}

resource "aws_subnet" "private" {
  for_each = { for idx in [0, 1] : "private-${idx + 1}" => { index = 10 + idx } }

  vpc_id     = aws_vpc.this.id
  cidr_block = cidrsubnet(aws_vpc.this.cidr_block, 8, each.value.index)

  tags = merge(local.effective_tags, {
    Name = "${var.project_name}-${each.key}"
    Tier = "private"
  })
}
