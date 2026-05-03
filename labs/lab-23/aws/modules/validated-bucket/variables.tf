variable "bucket_name" {
  type        = string
  description = "Nombre del bucket S3. Debe comenzar con el prefijo corporativo 'empresa-' y cumplir las reglas de naming de S3 (3-63 caracteres totales)."

  # Regex desglosada:
  #   ^empresa-           prefijo corporativo (8 chars)
  #   [a-z0-9]            primer caracter del sufijo (no punto/guion)  -> +1 char
  #   [a-z0-9.-]{1,53}    cuerpo (1 a 53 chars: minusculas, numeros, ., -)
  #   [a-z0-9]$           ultimo caracter (no punto/guion)              -> +1 char
  # Longitud total: minimo 11 chars (8 + 1 + 1 + 1) y maximo 63 chars
  # (8 + 1 + 53 + 1) — ajustado al limite de S3.
  validation {
    condition     = can(regex("^empresa-[a-z0-9][a-z0-9.-]{1,53}[a-z0-9]$", var.bucket_name))
    error_message = "El nombre del bucket debe comenzar con 'empresa-', contener solo minúsculas, números, puntos y guiones, y tener entre 11 y 63 caracteres en total."
  }
}

variable "force_destroy" {
  type        = bool
  description = "Permitir destruir el bucket aunque contenga objetos"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Etiquetas adicionales que se combinan con las del módulo"
  default     = {}
}
