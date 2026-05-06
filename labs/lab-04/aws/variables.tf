variable "region" {
  description = "Region de AWS donde se desplegaran los recursos."
  type        = string
  default     = "us-east-1"
}

# Map de usuarios IAM a crear. La clave es el nombre de usuario (each.key)
# y el valor contiene los metadatos que se asignarán como tags.
variable "iam_users" {
  type = map(object({
    department  = string
    cost_center = string
  }))

  default = {
    "alice" = { department = "engineering", cost_center = "CC-100" }
    "bob"   = { department = "finance", cost_center = "CC-200" }
    "carol" = { department = "engineering", cost_center = "CC-100" }
  }
}

# Prefijo usado para nombrar el launch template y sus tags
variable "app_name" {
  type    = string
  default = "corp-lab3"
}
