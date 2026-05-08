# ══════════════════════════════════════════════════════════════════════════════
# RECURSOS GLOBALES — viven en aws.core y los consumen las regiones
# ══════════════════════════════════════════════════════════════════════════════

data "aws_caller_identity" "core" {
  provider = aws.core
}

# ── KMS multi-region PRIMARY KEY (us-east-1) ────────────────────────────────
# `multi_region = true` marca esta CMK como elegible para tener réplicas en
# otras regiones. Cada región crea su propia replica desde el módulo
# `app-region/` referenciando este ARN. La primary y todas sus replicas
# comparten el mismo material criptográfico — un texto cifrado en cualquier
# región se puede descifrar en cualquier otra.
resource "aws_kms_key" "global_primary" {
  provider = aws.core

  description             = "KMS multi-region primary para ${var.project}"
  multi_region            = true
  enable_key_rotation     = true
  deletion_window_in_days = 7

  tags = {
    Name      = "${var.project}-kms-primary"
    Project   = var.project
    Region    = "us-east-1"
    Role      = "primary"
    ManagedBy = "terraform"
  }
}

resource "aws_kms_alias" "global_primary" {
  provider = aws.core

  name          = "alias/${var.project}-primary"
  target_key_id = aws_kms_key.global_primary.key_id
}

# ── VPC mínima en core, soporte de la zona privada ──────────────────────────
# Una hosted zone privada de Route53 debe asociarse a al menos una VPC para
# crearla. Esta VPC es solamente "soporte de la zona": no aloja workloads.
resource "aws_vpc" "core_support" {
  provider = aws.core

  cidr_block           = "10.0.0.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name      = "${var.project}-core-support"
    Project   = var.project
    Purpose   = "Soporte de la hosted zone privada"
    ManagedBy = "terraform"
  }
}

# ── Hosted Zone privada compartida ──────────────────────────────────────────
# Cada región registrará un CNAME aquí (euwest3.lab40.internal,
# apnortheast1.lab40.internal...) desde el propio módulo `app-region/`,
# usando el provider `aws.shared = aws.core`.
resource "aws_route53_zone" "private" {
  provider = aws.core

  name    = var.private_zone_name
  comment = "Zona privada compartida para descubrimiento regional de ${var.project}"

  vpc {
    vpc_id     = aws_vpc.core_support.id
    vpc_region = "us-east-1"
  }

  tags = {
    Name      = "${var.project}-private-zone"
    Project   = var.project
    ManagedBy = "terraform"
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# REGIÓN EU — eu-west-3 (París)
# ══════════════════════════════════════════════════════════════════════════════
#
# Instancia del módulo `app-region`. El bloque `providers = { ... }` mapea
# los alias DECLARADOS por el módulo (aws.this, aws.shared) a los providers
# REALES del root (aws.eu, aws.core). Esta es la pieza que hace funcionar
# `configuration_aliases`.
module "app_eu" {
  source = "./modules/app-region"

  providers = {
    aws.this   = aws.eu
    aws.shared = aws.core
  }

  project           = var.project
  primary_kms_arn   = aws_kms_key.global_primary.arn
  private_zone_id   = aws_route53_zone.private.zone_id
  private_zone_name = aws_route53_zone.private.name

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# REGIÓN JP — ap-northeast-1 (Tokio)
# ══════════════════════════════════════════════════════════════════════════════
#
# Misma fuente, distintos providers. El módulo no conoce ni le importa qué
# regiones está usando: solo sabe que tiene un `aws.this` para sus recursos
# regionales y un `aws.shared` para los compartidos.
module "app_jp" {
  source = "./modules/app-region"

  providers = {
    aws.this   = aws.jp
    aws.shared = aws.core
  }

  project           = var.project
  primary_kms_arn   = aws_kms_key.global_primary.arn
  private_zone_id   = aws_route53_zone.private.zone_id
  private_zone_name = aws_route53_zone.private.name

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
