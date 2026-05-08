#!/bin/bash
set -euo pipefail

# Instalar SSM Agent (AL2023 minimal no lo incluye)
dnf install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Instalar y configurar un servidor web basico para el health check del ALB
dnf install -y httpd

# Leer metadata via IMDSv2. AL2023 (sobre todo la variante minimal) no
# incluye el script `ec2-metadata` que existia en AL1/AL2; hay que usar
# el endpoint HTTP directamente con un token previo.
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)

cat > /var/www/html/index.html <<HTML
<!DOCTYPE html>
<html>
<body>
  <h1>Lab-18 — Seguridad y Control de Trafico en VPC</h1>
  <p>Instancia: ${INSTANCE_ID}</p>
  <p>AZ: ${AZ}</p>
</body>
</html>
HTML
systemctl enable httpd
systemctl start httpd
