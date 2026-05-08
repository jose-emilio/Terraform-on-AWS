variable "project" {
  type        = string
  description = "Prefijo del proyecto, usado para nombrar todos los recursos"
}

variable "primary_kms_arn" {
  type        = string
  description = <<-EOT
    ARN completo de la KMS multi-region primary key creada en aws.shared.
    Este ARN incluye la región de origen — AWS lo usa para localizar la
    primary y crear la replica en la región de aws.this.
  EOT
}

variable "private_zone_id" {
  type        = string
  description = "Zone ID de la hosted zone privada Route53 creada en aws.shared"
}

variable "private_zone_name" {
  type        = string
  description = "Nombre de la hosted zone privada (sin punto final). Usado como sufijo del CNAME regional"
}

variable "tags" {
  type        = map(string)
  description = "Tags comunes a todos los recursos del módulo"
  default     = {}
}
