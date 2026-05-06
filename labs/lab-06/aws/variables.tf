variable "region" {
  description = "Region de AWS donde se desplegaran los recursos."
  type        = string
  default     = "us-east-1"
}

# Valor del tag Env usado para localizar la VPC, subredes e instancias.
# Modificar este valor permite reutilizar la configuración en otros entornos.
variable "target_env" {
  type    = string
  default = "production"
}

# Sufijos de AZ que se consideran "principales" para el output filtrado.
# La expresión for con cláusula if seleccionará solo las AZs que terminen
# en alguno de estos sufijos.
variable "primary_az_suffixes" {
  type    = list(string)
  default = ["a", "b"]
}
