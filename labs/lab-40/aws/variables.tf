variable "account_id" {
  type        = string
  description = <<-EOT
    Account ID de la cuenta AWS donde residen los tres roles simulados
    (lab40-core-admin, lab40-eu-admin, lab40-jp-admin) creados en bootstrap/.

    En multi-cuenta REAL este valor sería el de cada cuenta destino y
    declararías una variable distinta por cada cuenta. Aquí los tres roles
    viven en la misma cuenta para que el lab sea ejecutable con un solo
    perfil AWS.

    Obténlo con:
      aws sts get-caller-identity --query Account --output text
  EOT

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "El account_id debe ser una cadena de 12 dígitos."
  }
}

variable "project" {
  type        = string
  description = "Prefijo que identifica todos los recursos del laboratorio"
  default     = "lab40"
}

variable "environment" {
  type        = string
  description = "Nombre del entorno (production, staging, dev)"
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "dev"], var.environment)
    error_message = "El entorno debe ser 'production', 'staging' o 'dev'."
  }
}

variable "private_zone_name" {
  type        = string
  description = <<-EOT
    Nombre de la hosted zone privada Route53 que se crea en aws.core y
    se asocia a la VPC de soporte. Cada región registra un CNAME bajo
    este sufijo (ej: euwest3.lab40.internal).

    Usa un sufijo claramente "interno": .internal, .corp, .private...
    Evita .local (reservado para mDNS) y dominios públicos reales.
  EOT
  default     = "lab40.internal"
}
