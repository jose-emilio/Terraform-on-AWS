# Sección 4 — Drift Avanzado y Reconciliación Continua

> [← Volver al índice](./README.md) | [Siguiente →](./05_migraciones_state.md)

---

## 1. Qué cubre esta sección y qué se asume

El [Módulo 3 §7.6-7.8](../modulo-03/07_estrategias_avanzadas.md) introdujo el concepto de drift y los mecanismos básicos de detección, y el [lab-12](../../labs/lab-12/README.md) te enseñó a detectarlo manualmente, reconciliar con la estrategia "Terraform gana" o "la realidad gana" y restaurar el state desde S3 versioning.

Esta sección no repite ese material. Se ocupa de la pregunta que viene después: **¿cómo se gestiona el drift en una organización con cientos de stacks y treinta personas tocando AWS?**

> **En la práctica:** "El drift no es un problema técnico, es un problema organizativo. Cuando solo tú tocas Terraform, el drift es un evento raro que arreglas en cinco minutos. Cuando lo tocan treinta personas, el drift es **constante** — un developer ajustó un security group durante un incidente, un script de cost-optimization redujo el desired_count de un ASG, AWS reescaló un Lambda. Tu trabajo deja de ser arreglar drift; tu trabajo es construir el sistema que detecta drift, lo clasifica, alerta solo del crítico, y deja pasar el resto sin ruido."

### 1.1 Lo que ya sabes (y este capítulo no repite)

| Tema | Dónde se vio |
|------|--------------|
| Qué es el drift | [Módulo 3 §7.6](../modulo-03/07_estrategias_avanzadas.md) |
| `terraform plan` para detectar drift | [lab-12](../../labs/lab-12/README.md) Fase 1 |
| `apply -refresh-only` básico | [lab-12](../../labs/lab-12/README.md) Reto 1 |
| Estrategias A/B (Terraform gana / realidad gana) | [lab-12](../../labs/lab-12/README.md) Fase 2 |
| Restaurar state desde S3 versioning | [lab-12](../../labs/lab-12/README.md) Fase 3 |

### 1.2 Lo que aprenderás aquí

| Tema | Sección |
|------|---------|
| Taxonomía profunda del drift y por qué la detección plana no escala | §2 |
| `check {}` blocks: validación continua no bloqueante | §3 |
| Drift detection programada en CI/CD: GitHub Actions y CodePipeline | §4 |
| Reconciliación selectiva con `-target` y `apply -refresh-only` parcial | §5 |
| Convivir con drift legítimo: `lifecycle { ignore_changes }` y patrones | §6 |
| Plataformas dedicadas: HCP Health Assessments, driftctl, Spacelift | §7 |
| Anti-patrones: cuándo "aceptar el drift" es la respuesta correcta | §8 |
| Hoja de ruta de madurez del drift management | §9 |

---

## 2. Taxonomía del drift: no todo drift es igual

La detección plana ("hay drift / no hay drift") falla en organizaciones grandes porque trata por igual al drift que destruye producción y al drift que es **operación normal del sistema**. El primer paso del drift management maduro es clasificar.

### 2.1 Por origen

| Origen | Ejemplo | Acción habitual |
|--------|---------|-----------------|
| **Manual humano** | Un developer cambió un Security Group desde la consola para destrabar un incidente | Reconciliar a Terraform; añadir auditoría sobre la persona |
| **Automatización externa** | Ansible que actualiza tags, script Bash que rota credenciales | Decidir: o bien trasladar la automatización a Terraform, o bien añadir `ignore_changes` y dejarla |
| **Servicio gestionado de AWS** | ASG cambia `desired_capacity`, Lambda cambia `published_version`, ECS reescala | Casi siempre `ignore_changes` — es el comportamiento esperado |
| **Apply parcial fallido** | Un `apply` murió a mitad: 7 recursos creados, 3 no | Reconciliación inmediata con `apply` completo |
| **Drift de proveedor** | AWS añadió un atributo nuevo al recurso que el provider ahora reporta | Upgrade del provider; raramente requiere acción |

### 2.2 Por estructura del cambio

```
Drift estructural          Drift configuracional       Drift transitorio
─────────────────         ───────────────────         ────────────────
Recurso añadido            Atributo cambió            Estado vuelve solo
o eliminado fuera          (ej: instance_type         (ej: ASG reescala
de Terraform               t3.micro → t3.large)       en pico de tráfico)

Severidad: ALTA            Severidad: MEDIA           Severidad: BAJA
Acción: import o           Acción: reconciliar        Acción: ignore_changes
        removed                                              o aceptar
```

> **Nota importante:** "El error más común al construir drift detection es alertar igual sobre todo. Acabas con un canal Slack que recibe 200 mensajes al día, el equipo lo silencia, y cuando llega el drift de verdad — el que un atacante introdujo modificando una IAM policy — pasa desapercibido entre el ruido. **Clasifica antes de alertar**."

### 2.3 Por intencionalidad

- **Drift legítimo conocido**: un campo que sabes que muta sin tu intervención (precios spot, tokens rotativos, contadores). Modélalo con `ignore_changes` desde el principio.
- **Drift legítimo nuevo**: aparece tras introducir una herramienta externa o un servicio gestionado. Decisión consciente: o lo absorbes en Terraform o lo registras como ignorado.
- **Drift ilegítimo**: todo lo demás. Es lo único que merece alerta.

---

## 3. `check {}` blocks: validación continua no bloqueante (TF 1.5+)

Las precondiciones y postcondiciones que viste en [lab-24](../../labs/lab-24/README.md) y [lab-39](../../labs/lab-39/README.md) **abortan el plan o el apply** si fallan. Eso es correcto para invariantes que rompen la infraestructura, pero es demasiado agresivo para drift detection: no quieres que un drift detectado en una alarma CloudWatch impida desplegar un cambio legítimo en otra capa.

`check {}` es el mecanismo intermedio: emite **warnings** sin detener la ejecución.

### 3.1 Anatomía

```hcl
check "endpoint_responde_ok" {
  # Data source scoped: solo se evalúa dentro del check
  data "http" "app_health" {
    url = "https://${aws_lb.main.dns_name}/health"
  }

  assert {
    condition     = data.http.app_health.status_code == 200
    error_message = "El ALB respondió ${data.http.app_health.status_code} en /health"
  }
}
```

Características clave:

- Se evalúa en cada `terraform plan` y `terraform apply`.
- El `data` que vive dentro del `check` solo se ejecuta dentro de ese contexto — no afecta al grafo de dependencias normal.
- Si el `assert` falla, Terraform muestra un warning amarillo y **continúa**.

### 3.2 Casos de uso reales

```hcl
# 1. Verificar conectividad HTTP del endpoint público
check "alb_responde" {
  data "http" "health" {
    url = "https://${aws_lb.main.dns_name}/health"
  }
  assert {
    condition     = data.http.health.status_code == 200
    error_message = "ALB responde ${data.http.health.status_code} en /health"
  }
}

# 2. Verificar que el ASG tiene al menos las réplicas mínimas declaradas
check "asg_replicas_minimas" {
  data "aws_autoscaling_group" "current" {
    name = aws_autoscaling_group.app.name
  }
  assert {
    condition     = data.aws_autoscaling_group.current.desired_capacity >= var.min_replicas
    error_message = "ASG tiene ${data.aws_autoscaling_group.current.desired_capacity} replicas; mínimo esperado ${var.min_replicas}"
  }
}

# 3. Verificar que la instancia EC2 sigue en estado "running"
check "ec2_running" {
  data "aws_instance" "web" {
    instance_id = aws_instance.web.id
  }
  assert {
    condition     = data.aws_instance.web.instance_state == "running"
    error_message = "Instancia ${aws_instance.web.id} en estado ${data.aws_instance.web.instance_state} (esperado: running)"
  }
}
```

> **Limitaciones de los scoped data sources** (documentación oficial): solo admiten los meta-argumentos `depends_on` y `provider`. **No** admiten `count`, `for_each` ni `lifecycle`. Si necesitas validar varios objetos del mismo tipo, declara un `check` por cada uno o usa data sources ya declarados fuera del bloque `check`. Además, los scoped data sources se evalúan **al final** del plan/apply, no durante la fase de planificación normal.

### 3.3 `check` vs `precondition` vs `postcondition`

| Mecanismo | Cuándo se evalúa | Si falla | Caso de uso |
|-----------|------------------|----------|-------------|
| `precondition` (lifecycle) | Antes del plan/apply del recurso | **Aborta** | Validar inputs antes de tocar nada |
| `postcondition` (lifecycle) | Después del apply del recurso | **Aborta** | Validar invariantes que rompen la infra |
| `check {}` | Cada plan/apply | Warning, continúa | Drift detection continuo, salud de endpoints |

> **En la práctica:** "Veo equipos que usan `postcondition` para todo. La consecuencia es que un fallo de salud de un endpoint bloquea el despliegue de un cambio en otra capa que no tiene nada que ver. Si el check no impide la operación que estás haciendo ahora mismo, la herramienta correcta es `check {}`, no `postcondition`. Reserva `postcondition` para cuando el recurso recién creado debe cumplir un invariante o no tiene sentido seguir."

---

## 4. Drift Detection programada en CI/CD

La regla de oro: **el drift detectado por una persona ya es tarde**. Cuando el equipo dice "se ha desconfigurado producción", llevas horas o días sin saberlo. La solución es ejecutar `terraform plan -refresh-only` periódicamente y alertar solo cuando el resultado se desvía.

### 4.1 El comando clave: `-detailed-exitcode`

```bash
$ terraform plan -refresh-only -detailed-exitcode

# Códigos de salida:
#   0 → No hay drift (estado declarado == realidad)
#   1 → Error en la ejecución (timeout, credenciales, etc.)
#   2 → Drift detectado (hay cambios entre state y realidad)
```

El código 2 es la pieza que permite construir lógica condicional en pipelines.

> **Nota importante:** "Existe un bug conocido en Terraform (issues hashicorp/terraform [#35117](https://github.com/hashicorp/terraform/issues/35117) y [#37406](https://github.com/hashicorp/terraform/issues/37406)) por el que `terraform plan -refresh-only -detailed-exitcode` puede devolver código 2 incluso cuando la salida en consola dice 'No changes'. Si tu pipeline encadena alertas a partir del exit code, **valida también la salida de texto** (por ejemplo `grep -q 'No changes' plan.out`) o usa el formato `-json` y filtra por la estructura del documento. Confiar solo en el exit code generará falsos positivos en algunas combinaciones de provider y versión."

### 4.2 GitHub Actions — implementación de referencia

```yaml
name: Drift Detection

on:
  schedule:
    - cron: '0 8 * * 1-5'   # Lunes a viernes a las 8AM UTC
  workflow_dispatch:         # Permitir ejecución manual

permissions:
  id-token: write            # Para OIDC con AWS
  contents: read

jobs:
  detect-drift:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        stack:                # Un job por stack independiente
          - networking
          - database
          - apps
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-drift-detection
          aws-region: us-east-1

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~1.10"

      - name: Terraform Init
        run: terraform init -input=false
        working-directory: stacks/${{ matrix.stack }}

      - name: Detect Drift
        id: plan
        run: terraform plan -refresh-only -detailed-exitcode -no-color
        working-directory: stacks/${{ matrix.stack }}
        continue-on-error: true   # Exit 2 NO debe fallar el job

      - name: Notify Slack on drift
        if: steps.plan.outputs.exitcode == '2'
        env:
          WEBHOOK: ${{ secrets.SLACK_WEBHOOK_DRIFT }}
        run: |
          curl -X POST "$WEBHOOK" -H 'Content-Type: application/json' -d "$(cat <<EOF
          {
            "text": ":warning: Drift detectado en stack ${{ matrix.stack }}",
            "attachments": [{
              "color": "warning",
              "fields": [
                {"title": "Stack", "value": "${{ matrix.stack }}", "short": true},
                {"title": "Acción", "value": "<https://github.com/${{ github.repository }}/actions/runs/${{ github.run_id }}|Ver run>", "short": true}
              ]
            }]
          }
          EOF
          )"

      - name: Fail job if exit code was an error (1)
        if: steps.plan.outputs.exitcode == '1'
        run: exit 1
```

Detalles importantes:

- `continue-on-error: true` solo en la step de `plan`: el exit 2 no debe fallar el workflow.
- Job matrix por stack: cada uno tiene su propia frecuencia de drift y su propio runbook.
- OIDC en lugar de keys estáticas (consistente con [lab-16](../../labs/lab-16/README.md)).
- Notificación a Slack diferenciada de un error real (exit 1) vs drift (exit 2).

### 4.3 AWS CodePipeline — implementación nativa

En entornos donde GitHub Actions no es viable (cuentas air-gapped, política corporativa), CodePipeline puede orquestar lo mismo:

```hcl
resource "aws_codebuild_project" "drift_detector" {
  name         = "terraform-drift-detection"
  service_role = aws_iam_role.codebuild_drift.arn

  artifacts { type = "NO_ARTIFACTS" }
  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"
    type         = "LINUX_CONTAINER"
  }

  source {
    type      = "NO_SOURCE"
    buildspec = <<-YAML
      version: 0.2
      phases:
        install:
          commands:
            - curl -fsSL https://releases.hashicorp.com/terraform/1.10.5/terraform_1.10.5_linux_amd64.zip -o tf.zip
            - unzip tf.zip && mv terraform /usr/local/bin/
        build:
          commands:
            - aws s3 cp s3://my-config-bucket/stacks/${STACK_NAME}.tar.gz code.tgz
            - tar xzf code.tgz && cd stacks/$${STACK_NAME}
            - terraform init -input=false
            - |
              terraform plan -refresh-only -detailed-exitcode || EXITCODE=$?
              if [ "$${EXITCODE:-0}" = "2" ]; then
                aws sns publish \
                  --topic-arn $${SNS_TOPIC_DRIFT} \
                  --subject "Drift detectado en $${STACK_NAME}" \
                  --message "Revisar el log de CodeBuild"
              fi
              exit 0
    YAML
  }
}

resource "aws_cloudwatch_event_rule" "drift_schedule" {
  name                = "terraform-drift-daily"
  schedule_expression = "cron(0 8 ? * MON-FRI *)"
}

resource "aws_cloudwatch_event_target" "drift_codebuild" {
  rule     = aws_cloudwatch_event_rule.drift_schedule.name
  arn      = aws_codebuild_project.drift_detector.arn
  role_arn = aws_iam_role.eventbridge_invoke_codebuild.arn
}
```

### 4.4 Frecuencia y blast radius

| Frecuencia | Stacks | Ventaja | Inconveniente |
|------------|--------|---------|---------------|
| Cada hora | Producción crítica | Detecta drift en minutos | Coste y ruido si hay drift continuo legítimo |
| Diaria laborable | Stacks de aplicación | Equilibrio coste/visibilidad | Drift de fin de semana se ve el lunes |
| Semanal | Sandboxes, dev | Mínimo ruido | Solo útil para auditoría histórica |
| Bajo demanda | Stacks experimentales | Sin coste recurrente | Solo se sabe del drift cuando se busca |

> **Nota importante:** "Empieza con frecuencia diaria laborable y solo prod. Cuando estés cómodo con el ruido y los procesos de respuesta funcionen, **entonces** sube a horario. Empezar con horario en todos los stacks a la vez es la receta para que el equipo silencie el canal de alertas en una semana."

---

## 5. Reconciliación selectiva

El [lab-12](../../labs/lab-12/README.md) te enseñó `apply -refresh-only` global. En la práctica casi nunca lo querrás aplicar a todo: detectas drift en un recurso concreto y necesitas reconciliar **solo ese**.

### 5.1 `-target` con `refresh-only`

```bash
# Aceptar el drift solo en un recurso (sin tocar el resto)
$ terraform apply -refresh-only -target=aws_security_group.web

# Aceptar drift en varios recursos relacionados
$ terraform apply -refresh-only \
    -target=aws_security_group.web \
    -target=aws_security_group.api
```

### 5.2 `-target` con `apply` normal: revertir drift selectivo

```bash
# Revertir drift en un recurso (forzar el estado declarado)
$ terraform apply -target=aws_security_group.web

# El plan generado solo incluye ese recurso y sus dependencias
```

### 5.3 Cuándo NO usar `-target`

| Situación | Por qué evitar `-target` |
|-----------|--------------------------|
| Drift en cascada (un recurso afecta a varios) | `-target` puede dejar dependencias inconsistentes |
| Drift de producción durante un incidente | El equipo de oncall no debe usar flags raros bajo presión |
| Drift en un módulo entero | Un `-target=module.networking` aplica a todo el módulo y suele ser excesivo |
| Como herramienta habitual | Documentación oficial: "use `-target` for exceptional circumstances only" |

> **En la práctica:** "`-target` es el equivalente del `git rebase -i`: poderoso, peligroso, y la mayoría de las veces que crees necesitarlo en realidad necesitas otra cosa. Si te encuentras usando `-target` más de una vez al mes, hay un problema estructural — probablemente el state es demasiado grande y el módulo 5 (state splitting) sería más adecuado."

### 5.4 Reconciliación post-incidente: el patrón "snapshot + apply"

Tras un incidente donde alguien tocó la consola, el procedimiento limpio:

```bash
# 1. Snapshot del state actual (auditoría posterior)
$ terraform state pull > pre-reconcile-$(date +%s).json

# 2. Plan completo para entender el alcance
$ terraform plan -refresh-only -no-color > drift-report.txt

# 3. Decisión consciente:
#    Opción A — Aceptar todo el drift (la realidad gana)
$ terraform apply -refresh-only

#    Opción B — Revertir todo el drift (Terraform gana)
$ terraform apply

#    Opción C — Aceptar parcial, revertir el resto (caso más común)
$ terraform apply -refresh-only -target=aws_security_group.web   # acepto este
$ terraform apply -target=aws_iam_policy.app                     # revierto este

# 4. Snapshot post-reconciliación
$ terraform state pull > post-reconcile-$(date +%s).json

# 5. ADR archivado con: motivo del drift, decisión tomada, hash de los snapshots
```

---

## 6. Convivir con drift legítimo: `lifecycle { ignore_changes }`

Algunos atributos **están diseñados** para mutar fuera de Terraform. Ignorarlos no es ocultar drift — es modelarlos correctamente.

### 6.1 Patrón ASG: `desired_capacity` gestionado por scaling policies

```hcl
resource "aws_autoscaling_group" "app" {
  name             = "app-asg"
  min_size         = 2
  max_size         = 20
  desired_capacity = 4   # valor inicial; las scaling policies lo van a cambiar

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  lifecycle {
    ignore_changes = [
      desired_capacity,   # ASG lo cambia con el tráfico, no nosotros
      target_group_arns,  # Modificado por CodeDeploy blue/green (lab-44)
    ]
  }
}
```

### 6.2 Patrón ECS: `desired_count` gestionado por App Auto Scaling

```hcl
resource "aws_ecs_service" "api" {
  name            = "api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 2

  lifecycle {
    ignore_changes = [
      desired_count,    # App Auto Scaling lo gestiona
      task_definition,  # Si despliegas con CodeDeploy, este cambia fuera de Terraform
    ]
  }
}
```

### 6.3 Patrón Lambda: published_version y alias

```hcl
resource "aws_lambda_function" "api" {
  function_name = "api-handler"
  role          = aws_iam_role.lambda.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  publish       = true

  s3_bucket = aws_s3_bucket.artifacts.id
  s3_key    = "lambda/api.zip"

  lifecycle {
    ignore_changes = [
      s3_key,             # CI/CD lo actualiza en cada release
      source_code_hash,   # Cambia con cada s3_key
    ]
  }
}
```

### 6.4 Patrón AMI rolling: `image_id` actualizado por automation externa

```hcl
resource "aws_launch_template" "app" {
  name_prefix = "app-"
  image_id    = data.aws_ami.amazon_linux.id   # valor inicial

  lifecycle {
    ignore_changes = [image_id]  # Pipeline externo actualiza la AMI
    create_before_destroy = true
  }
}
```

### 6.5 El anti-patrón: `ignore_changes = all`

```hcl
# NO HACER (salvo casos justificadísimos):
resource "aws_iam_policy" "app" {
  name   = "app-policy"
  policy = jsonencode({...})

  lifecycle {
    ignore_changes = all   # ← apaga la detección de drift sobre TODO el recurso
  }
}
```

`ignore_changes = all` desactiva drift detection sobre el recurso entero. Solo es legítimo en escenarios muy concretos (recursos generados por una integración externa cuya forma exacta no controlas). En la mayoría de los casos significa "no quiero pensar qué atributos pueden mutar" — y eso es deuda técnica disfrazada.

> **Nota importante:** "Cada `ignore_changes` que pongas es una pequeña área del recurso donde Terraform deja de ser la fuente de verdad. Eso está bien si la decisión es consciente. Es desastroso si se acumula: he visto módulos con 15 atributos ignorados donde nadie sabía ya cuál era el comportamiento esperado del recurso. Documenta cada `ignore_changes` con un comentario explicando **quién** modifica ese atributo y **por qué** Terraform no debe pelear."

---

## 7. Plataformas dedicadas de drift detection

Cuando la organización supera ~50 stacks, montar drift detection con GitHub Actions o CodePipeline a mano se vuelve costoso de mantener. Existen plataformas especializadas:

### 7.1 Comparativa rápida

| Plataforma | Tipo | Drift continuo | Visualización | Coste |
|------------|------|----------------|---------------|-------|
| **HCP Terraform** (Standard/Premium) | SaaS HashiCorp | Health Assessments cada 24h | Dashboard nativo | Por workspace/mes |
| **driftctl** | CLI open source | Bajo demanda o cron propio | Salida JSON/CLI | Gratis (ver nota) |
| **Spacelift** | SaaS | Continuo, configurable, remediación automática opcional | Dashboard rico | Por usuario/mes |
| **env0** | SaaS | Continuo, con análisis de causa | Dashboard con root-cause | Por usuario/mes |
| **Scalr** | SaaS / self-hosted | Continuo, con análisis de causa | Dashboard | Por workspace |
| **AWS Config + Custom Rules** | AWS nativo | Continuo (Config rules) | AWS Console | Por evaluación |

### 7.2 HCP Terraform Health Assessments

Si ya usas HCP Terraform como backend (lab-10), Health Assessments es una activación, no una integración. La feature está disponible en los planes **Standard** y **Premium** (consulta el [pricing oficial](https://www.hashicorp.com/products/terraform/pricing) para validar el plan vigente — los nombres de los tiers han cambiado varias veces).

```
HCP Terraform UI → Workspace → Settings → Health
  → Enable Health Assessments
  → Frequency: every 24 hours (no configurable a la baja)
  → Notify: Slack/email cuando se detecta drift
```

El sistema ejecuta `plan -refresh-only` automáticamente y agrega los resultados en un dashboard cross-workspace.

**Requisitos** (documentación oficial):

- Terraform ≥ 1.3.0
- Modo de ejecución **Remote** o **Agent** (no funciona en modo Local)
- El último run del workspace debe haber sido exitoso

### 7.3 driftctl: detectar recursos NO gestionados

> **Nota sobre el estado del proyecto:** driftctl está en **maintenance mode** desde junio de 2023 (anuncio oficial de Snyk). El repositorio sigue activo con releases ocasionales y la herramienta es funcional, pero el desarrollo de nuevas features se ha detenido. Antes de adoptarla en 2026+, evalúa alternativas vivas o asume que la cobertura de recursos AWS no incorporará nuevos servicios.

driftctl ataca el problema inverso a `terraform plan`: detectar recursos en AWS que **no** están en ningún state de Terraform — el "shadow IT" de la cuenta.

```bash
$ driftctl scan \
    --from tfstate+s3://tfstate-bucket/prod/terraform.tfstate \
    --to aws+iam,ec2,s3,rds

Found resources:
  Managed: 142
  Unmanaged: 27   ← recursos en AWS que ningún state controla
  Drifted: 3      ← recursos en state que no coinciden con AWS
  Deleted: 1      ← en state pero borrado en AWS
```

Útil para auditorías periódicas de "qué tenemos en la cuenta que no controlamos con Terraform".

### 7.4 Cuándo construir vs comprar

| Síntoma | Recomendación |
|---------|---------------|
| <10 stacks, equipo de 1-3 personas | GitHub Actions / CodePipeline a mano (§4) |
| 10-50 stacks, equipo de 5-15 personas | GitHub Actions con matrix + dashboard custom o HCP Terraform |
| 50+ stacks, equipo de 15+ personas | Plataforma dedicada (Spacelift, env0, Scalr o HCP Terraform Plus) |
| Necesidad de auditoría regulatoria | AWS Config + driftctl + plataforma con audit log inmutable |

---

## 8. Anti-patrones del drift management

### 8.1 Alertar de todo

Ya cubierto en §4.4 — el resultado predecible es que el equipo silencia el canal y el drift de verdad pasa desapercibido. **Clasifica antes de alertar.**

### 8.2 Reconciliar a ciegas con `apply` automático

```yaml
# NO HACER
on:
  schedule: [{ cron: '0 * * * *' }]
jobs:
  reconcile:
    steps:
      - run: terraform apply -auto-approve   # ← peligro
```

Aplicar automáticamente lo que detecta el drift detection significa que **AWS no es la fuente de verdad cuando hay drift, ni Terraform tampoco**: el último que ejecutó gana, y eso es indeterminismo. La reconciliación siempre debe pasar por revisión humana o por una política explícita ("rollback automático solo en producción y solo si el drift afecta a SG/IAM").

### 8.3 Ignorar drift "porque siempre vuelve"

```hcl
# Síntoma: el alumno ve que el drift de un atributo X reaparece tras cada apply,
# y "soluciona" el problema con:
lifecycle {
  ignore_changes = [X]
}
```

A veces es correcto (§6). A veces oculta un bug del provider, una configuración de un servicio gestionado mal documentada, o un script externo que nadie sabe que existe. **Antes de ignorar, investiga el origen.**

### 8.4 Detectar drift sin runbook de respuesta

Tener un canal Slack que recibe alertas de drift **sin un runbook claro de qué hacer** es solo ruido. El runbook mínimo:

```markdown
## Runbook: drift detectado en stack <X>

1. ¿El drift es esperado? (ver §6 y la lista de atributos ignorados conocidos)
   → Sí: actualizar la lista de "drift legítimo", cerrar la alerta
   → No: continuar

2. ¿El drift afecta a IAM, SG, KMS, o un recurso de producción crítico?
   → Sí: escalar a oncall de seguridad inmediato
   → No: continuar

3. ¿El drift es estructural (recurso añadido/eliminado) o configuracional?
   → Estructural: revisar logs de CloudTrail para identificar el origen
   → Configuracional: continuar

4. Decisión consciente:
   → Aceptar (terraform apply -refresh-only -target=...)
   → Revertir (terraform apply -target=...)
   → Importar al state si es un recurso nuevo legítimo

5. Archivar ADR con la decisión y reabrir alerta solo si reaparece.
```

### 8.5 Confundir drift con desync de la versión del provider

Síntoma: tras un upgrade del provider AWS aparecen "drifts" en atributos que nadie tocó. Causa: el nuevo provider expone atributos que el anterior no leía. **No es drift real**; un `apply -refresh-only` cierra el caso. Cubierto en detalle en [§7 de la sección 5](./05_migraciones_state.md).

---

## 9. Hoja de ruta de madurez

Una manera de evaluar dónde está tu organización y hacia dónde ir:

| Nivel | Características | Acción siguiente |
|-------|----------------|------------------|
| **0 — Ciego** | Nadie sabe qué hay en la cuenta; consola y Terraform conviven sin reglas | Inventariar: `driftctl scan` para entender el alcance |
| **1 — Reactivo** | El drift se descubre cuando rompe algo en producción | Programar `plan -refresh-only` semanal en el stack más crítico |
| **2 — Detectivo** | Drift detection programado en CI/CD, alertas a Slack | Clasificar alertas por severidad (§2); añadir runbook (§8.4) |
| **3 — Selectivo** | Drift legítimo modelado con `ignore_changes`; alertas solo de drift ilegítimo | Migrar a plataforma dedicada si superas 50 stacks |
| **4 — Preventivo** | Policy-as-code (Sentinel/OPA) bloquea cambios en consola; SCPs prohíben acciones manuales en prod | Auditoría continua con AWS Config + Conformance Packs |
| **5 — Inmutable** | Cero drift por diseño: la consola es solo lectura; toda mutación pasa por PR + CI | Mantener: el reto deja de ser técnico y pasa a ser cultural |

> **En la práctica:** "La mayoría de organizaciones que conozco están en nivel 2. Subir al 3 cuesta entre tres y seis meses de trabajo serio: clasificar todo el drift histórico, modelar los `ignore_changes` legítimos, escribir los runbooks. Subir del 3 al 5 no es un proyecto técnico — es cultural. Implica que el equipo de operaciones acepte que durante un incidente **no van a tocar la consola**, sino a hacer un PR de emergencia. Eso requiere madurez organizativa, no más Terraform."

---

## Resumen y siguiente paso

Has visto cómo escalar el drift management más allá del `terraform plan` manual del lab-12: clasificar drift por origen, estructura e intencionalidad; usar `check {}` para validación continua no bloqueante; programar drift detection en GitHub Actions y CodePipeline con `-detailed-exitcode`; reconciliar selectivamente con `-target`; modelar drift legítimo con `lifecycle { ignore_changes }`; y elegir entre construir o comprar plataformas dedicadas.

La sección §5 cubre el siguiente nivel: cuando el drift no es solo configuracional sino que necesitas **mover, fusionar, reparar o migrar el state** entre proyectos, versiones o backends.

---

> [← Volver al índice](./README.md) | [Siguiente →](./05_migraciones_state.md)
