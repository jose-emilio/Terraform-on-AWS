# Módulo `app-region` — declaración de providers requeridos
#
# Este módulo NO declara los providers — los recibe del root module mediante
# `configuration_aliases`. Esta es la forma correcta de declarar que un módulo
# necesita MÚLTIPLES providers AWS configurados (uno por región/cuenta) sin
# instanciarlos él mismo.
#
# Quien instancia el módulo debe pasarle los providers explícitamente:
#
#   module "app_eu" {
#     source = "./modules/app-region"
#     providers = {
#       aws.this   = aws.eu     # provider de la región donde se despliega la app
#       aws.shared = aws.core   # provider de la cuenta core (donde vive la zona DNS)
#     }
#     ...
#   }

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"

      configuration_aliases = [
        aws.this,   # región donde se despliegan los recursos de aplicación
        aws.shared, # cuenta core (recursos compartidos cross-region: DNS, KMS primary)
      ]
    }
  }
}
