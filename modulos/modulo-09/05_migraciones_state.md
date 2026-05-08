# Sección 5 — Migraciones Complejas de State

> [← Volver al índice](./README.md) | [Siguiente →](./06_rendimiento_escala.md)

---

## 1. Cuando `moved` no es suficiente

A estas alturas del curso ya conoces el trío declarativo `import` / `moved` / `removed` ([lab-08](../../labs/lab-08/README.md)) y los fundamentos de state, locking y disaster recovery del [Módulo 3](../modulo-03/README.md). Esos mecanismos resuelven el 90% de los movimientos del día a día. Esta sección se ocupa del 10% restante: las situaciones que aparecen al cabo de **dos o tres años** manteniendo Terraform en producción y para las que `moved` no basta.

> **En la práctica:** "El primer año con Terraform refactorizas con `moved` y todo funciona. El segundo año el provider AWS sube de v4 a v5 y el state empieza a quejarse de schemas. El tercer año fusionas un equipo, heredas un state ajeno y quieres unificarlo. Ese tercer año es cuando descubres que tienes que conocer las herramientas de cirugía del state — y conocerlas bien, porque ya estás operando sobre infraestructura real con clientes encima."

Los **tres escenarios** que estudiamos en esta sección y que `moved` **no** cubre:

1. **El recurso vive en otro `tfstate`** — otro proyecto, otra capa, otra cuenta.
2. **El esquema del provider cambió** — atributos renombrados, deprecated, tipos cambiados, namespace reasignado.
3. **El state está corrupto, bloqueado o desincronizado** — la herramienta que normalmente lee y escribe el state ya no puede.

### 1.1 Tabla decisora: ¿qué herramienta uso?

| Síntoma | Herramienta correcta | Sección |
|---------|----------------------|---------|
| Renombrar un recurso dentro del mismo state | Bloque `moved` | (lab-08) |
| Adoptar un recurso preexistente | Bloque `import` | (lab-08) |
| Dejar de gestionar un recurso sin destruirlo | Bloque `removed` | (lab-08) |
| Mover un recurso a otro `tfstate` | `terraform state mv -state-out` | §4 |
| Fusionar dos `tfstate` en uno | `terraform state mv -state -state-out` | §5 |
| Subir de versión mayor de Terraform | `terraform 0.13upgrade` + `init -upgrade` | §2 |
| Cambiar el namespace del provider | `terraform state replace-provider` | §3 |
| Aparece `Error: state lock acquired by ...` | `terraform force-unlock` (con investigación) | §6 |
| `Error: state was created by Terraform vX.Y` | Pull, edición controlada, push | §7 |
| Migrar el backend a otra cuenta o servicio | `init -migrate-state` o pull/push manual | §9 |

> **Nota importante:** "Cada fila de esta tabla es un comando que puede destruir producción si lo aplicas en el escenario equivocado. La regla es: **antes de tocar el state, haz backup**. Sin excepciones. `terraform state pull > backup.$(date +%s).json` es un comando barato; recuperarse de un `state push` mal hecho puede costar días."

---

## 2. Migración de versión: 0.12 → 1.x → OpenTofu

Terraform tiene una política de compatibilidad **asimétrica**: una versión más nueva puede leer y actualizar un state escrito por una versión anterior, pero una versión anterior **no puede** leer un state escrito por una más nueva. Esto convierte cada upgrade mayor en una operación irreversible — una vez actualizado el state, ya no se puede volver atrás sin restaurar el backup.

### 2.1 Anatomía del state respecto a versiones

```bash
# Ver la cabecera del state actual
$ terraform state pull | jq '{version, terraform_version, serial, lineage}'
{
  "version": 4,
  "terraform_version": "1.7.5",
  "serial": 142,
  "lineage": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

| Campo | Significado | Implicación en migración |
|-------|-------------|--------------------------|
| `version` | Formato del state (1-4) | Cambia con upgrades muy mayores. Versión 4 estable desde 0.13 |
| `terraform_version` | Versión exacta de Terraform que escribió | Bloquea ejecución desde versiones inferiores |
| `serial` | Contador de cambios | Útil para detectar applies concurrentes |
| `lineage` | UUID único del state | **Nunca** debe cambiar — si cambia, perdiste el linaje |

### 2.2 Plan de migración seguro 0.12 → 1.x

La migración por saltos pequeños evita acumular errores. Aunque parezca tentador "saltar directo a 1.7", la herramienta de upgrade automático solo está diseñada para incrementos puntuales:

```bash
# Estado de partida: terraform 0.12.31

# Paso 1 — Subir a 0.13 con la herramienta de upgrade
$ tfenv install 0.13.7 && tfenv use 0.13.7
$ terraform 0.13upgrade   # Reescribe required_providers
$ terraform init           # Migra el state
$ terraform plan           # Debe mostrar "No changes"

# Paso 2 — Subir a 0.14, 0.15, 1.0 (un salto cada vez)
$ tfenv install 0.14.11 && tfenv use 0.14.11 && terraform plan
$ tfenv install 0.15.5  && tfenv use 0.15.5  && terraform plan
$ tfenv install 1.0.11  && tfenv use 1.0.11  && terraform plan

# Paso 3 — A partir de 1.0, los saltos pueden ser más largos
$ tfenv install 1.7.5 && tfenv use 1.7.5 && terraform plan
```

La regla de oro: **`terraform plan` debe devolver `No changes` después de cada salto**. Si aparecen cambios, el upgrade ha tocado algo del schema y hay que entenderlo antes de seguir.

### 2.3 Migración a OpenTofu

OpenTofu nació en agosto de 2023 como fork de Terraform **1.5.7**, tras el cambio de Terraform a la licencia BSL. Desde entonces ambos productos divergen: Terraform sigue con licencia BSL en la línea 1.6 → 1.14 → 1.15 (alpha), y OpenTofu evoluciona con licencia MPL-2.0 en la línea 1.6 → 1.11. En abril de 2025 OpenTofu fue aceptado en la **CNCF como proyecto Sandbox**.

> **Nota importante:** "Mucha documentación en internet — incluida la oficial antigua — describe la migración a OpenTofu como un *rebranding* trivial. Eso era cierto en 2023, cuando ambos productos eran prácticamente idénticos. **No lo es hoy.** A mayo de 2026, con Terraform 1.14 y OpenTofu 1.11, llevan casi tres años divergiendo y existen features exclusivas en cada lado, además de campos del state que pueden no entenderse correctamente entre uno y otro. Antes de migrar producción, audita siempre qué features post-1.5.7 está usando tu código."

La complejidad real de la migración depende de **desde qué versión de Terraform partes**:

| Desde | Hacia | Dificultad | Tratamiento |
|-------|-------|------------|-------------|
| Terraform ≤ 1.5.x | OpenTofu 1.6+ | Baja — funcionalmente un rebranding | §2.3.1 |
| Terraform 1.6 – 1.14+ | OpenTofu 1.11+ | **Media-alta** — auditoría obligatoria | §2.3.2 |

#### 2.3.1 Caso fácil: desde Terraform ≤ 1.5.x

Cuando el código de partida nunca pasó del punto del fork, no usa ninguna feature exclusiva de Terraform 1.6+, y el state fue escrito por una versión que OpenTofu conoce bien. El procedimiento es prácticamente un cambio de binario:

```bash
# 1. Instalar tofu junto a terraform (sin alias, para poder ejecutar ambos durante la transición)
$ which terraform   # /usr/local/bin/terraform
$ which tofu        # /usr/local/bin/tofu

# 2. Re-init para reescribir la cabecera del state con la versión de OpenTofu
$ tofu init -migrate-state

# 3. Verificar que el lineage se preserva (es la huella del state — no debe cambiar)
$ tofu state pull | jq '.lineage'
"a1b2c3d4-e5f6-7890-abcd-ef1234567890"  # mismo UUID que antes

# 4. Plan limpio
$ tofu plan   # esperado: No changes
```

> **En la práctica:** "Si tu equipo dejó de actualizar Terraform en 2023 por la incertidumbre del cambio de licencia, estás en este caso. La migración a OpenTofu es funcionalmente un rebranding y el state se reescribe sin pérdida de información. El trabajo real está en validar que tu pipeline CI/CD reconoce el binario `tofu`, que las imágenes Docker corporativas lo tienen durante la transición, y que tu Registry interno acepta los nuevos campos del manifiesto."

#### 2.3.2 Caso real en 2026+: desde Terraform 1.6+ (auditoría obligatoria)

Si tu código se ha mantenido al día con Terraform tras el fork (1.6, 1.7, ..., 1.14), la migración **no es un rebranding**. Tres categorías de problemas:

**Problema 1 — Features exclusivas de Terraform que OpenTofu no implementa:**

| Feature | Introducida en | ¿Existe en OpenTofu? |
|---------|---------------|---------------------|
| `ephemeral` resources y valores ephemeral | Terraform 1.10 (resources, vars, outputs) y 1.11 (write-only en managed resources) | No |
| `terraform test` con `mock_provider`, `override_resource`, `override_data`, `override_module` | Terraform 1.7 | Parcial — OpenTofu 1.8 añadió `mock_provider`; los overrides de resource/data/module siguen siendo terreno divergente (issue #1204 en opentofu/opentofu) |
| Terraform Stacks | Beta privada en 2024; **GA tras HashiConf 2024** (subcomando `terraform stacks` en TF 1.11+) | No |

Si tu HCL usa `ephemeral { ... }` o referencia Stacks, **OpenTofu fallará al parsear el código**. Hay que reescribir esas partes antes de migrar.

**Problema 2 — Features exclusivas de OpenTofu que el equipo puede querer adoptar:**

| Feature | Introducida en | Caso de uso |
|---------|---------------|-------------|
| State and Plan Encryption nativa | OpenTofu 1.7 | Cifrado del state sin depender de KMS externo ni del backend |
| Early variable evaluation | OpenTofu 1.8 | Variables y locals utilizables en `backend {}`, `module source` y configuración de cifrado |
| Flag `-exclude` | OpenTofu 1.9 | Operación inversa a `-target`: excluir un recurso del plan/apply |
| Provider `for_each` (multi-instancia con alias) | OpenTofu 1.9 | Multi-región y multi-cuenta sin replicar bloques `provider` manualmente |
| Meta-argumento `enabled` en `lifecycle` | OpenTofu 1.11 | Despliegue condicional sin trucos con `count`/`for_each` |

> **Nota importante:** algunas comparativas antiguas presentaban "provider-defined functions" como exclusiva de OpenTofu (1.7). **No lo son**: Terraform 1.8 (mayo 2024) las introdujo también. Verifica siempre la versión vigente de cada producto antes de basar una decisión de migración en una "exclusividad" que puede haber sido absorbida por el otro lado.

Estas no rompen la migración pero suelen ser la **razón** por la que se migra.

**Problema 3 — Divergencia del formato del state desde 1.6+:**

Algunos campos de metadatos del state se escriben de forma sutilmente distinta a partir de Terraform 1.6+. Aunque el `lineage`, `serial`, `version` y la estructura de `resources[]` siguen siendo idénticos, hay atributos a nivel de provider y de schema que pueden requerir un `tofu apply -refresh-only` para reescribirse limpiamente.

**Procedimiento recomendado (oficial OpenTofu):**

```bash
# 1. Auditoría previa de HCL — buscar features post-fork
$ grep -rE '\bephemeral\s+("|\{)' .                         # ephemeral { ... } y ephemeral "<tipo>"
$ find . \( -name '*.tfcomponent.hcl' -o -name '*.tfdeploy.hcl' \)   # Terraform Stacks
# Si hay matches en cualquiera de los dos, decidir reescritura antes de continuar

# 2. Probar primero en un entorno NO productivo
$ cd entornos/dev/
$ terraform state pull > backup-pre-migration.json   # con el binario actual
$ tofu init -migrate-state                            # con el binario de OpenTofu
$ tofu plan                                           # debe ser No changes

# 3. Refresh para reescribir metadatos divergentes
$ tofu apply -refresh-only

# 4. Recomendación oficial: si vienes de Terraform 1.5.x o anterior,
#    sigue la guía paso a paso de cada serie:
#      https://opentofu.org/docs/intro/migration/
#    A mayo 2026 OpenTofu va por la serie 1.11; consulta la guía
#    correspondiente a tu Terraform de origen.

# 5. Solo tras éxito en dev → staging → prod, con freeze entre etapas
```

> **Nota importante:** "Si tu equipo está en Terraform 1.10 o superior y usa `ephemeral`, no tienes una ruta directa a OpenTofu 1.11 hoy. Tienes tres opciones: (a) bajar el código a un subset compatible con OpenTofu, (b) esperar a que OpenTofu implemente la feature, (c) quedarte en Terraform asumiendo la licencia BSL. La decisión es tanto técnica como de licenciamiento — no la tomes solo en función del comando `tofu init -migrate-state`."

**Material de referencia oficial** (consultar versión actual antes de migrar):

- [opentofu.org/docs/intro/migration](https://opentofu.org/docs/intro/migration/) — guía oficial general
- [opentofu.org/docs/v1.9/intro/migration/terraform-1.9/](https://opentofu.org/docs/v1.9/intro/migration/terraform-1.9/) — guía específica desde Terraform 1.9 (consultar la versión equivalente para tu Terraform de origen)

### 2.4 Anti-patrón: editar el campo `version` a mano

```bash
# NO HACER:
$ terraform state pull > state.json
$ sed -i 's/"terraform_version": "1.7.5"/"terraform_version": "1.0.0"/' state.json
$ terraform state push state.json
```

Funciona el primer día. Falla el segundo, cuando el provider AWS intenta deserializar un atributo introducido en v5 sobre un binario que solo lo conoce en v4. El resultado típico: el recurso aparece como "creación" en el plan, listo para destruir y recrear producción.

---

## 3. `terraform state replace-provider` — cambio de namespace

El comando `state replace-provider` actualiza la referencia al provider dentro del state sin tocar los recursos. Resuelve dos casos clásicos:

### 3.1 Migración del registry "legacy" al "hashicorp"

Antes de Terraform 0.13 los providers vivían en `registry.terraform.io/-/<nombre>`. Desde 0.13 todos pasaron a `registry.terraform.io/hashicorp/<nombre>`. Si tu state es viejo, lo verás:

```bash
$ terraform plan
Error: Failed to query available provider packages

Could not retrieve the list of available versions for provider -/aws

# Solución:
$ terraform state replace-provider \
    'registry.terraform.io/-/aws' \
    'registry.terraform.io/hashicorp/aws'

Terraform will perform the following actions:
  ~ Updating provider:
    - registry.terraform.io/-/aws
    + registry.terraform.io/hashicorp/aws

Changing 47 resources:
  aws_vpc.main
  aws_subnet.public[0]
  ...

Do you want to make these changes? Only 'yes' will be accepted.
```

### 3.2 Migración a un mirror corporativo o a OpenTofu Registry

```bash
# Mirror corporativo: el provider sigue siendo el mismo binario,
# pero el state debe apuntar al endpoint privado para evitar
# llamadas al registry público desde redes restringidas
$ terraform state replace-provider \
    'registry.terraform.io/hashicorp/aws' \
    'registry.empresa.com/aws-internal/aws'

# OpenTofu Registry
$ tofu state replace-provider \
    'registry.terraform.io/hashicorp/aws' \
    'registry.opentofu.org/hashicorp/aws'
```

> **Nota importante:** "Si abres el state heredado de un equipo y ves un error tipo `Provider source not available`, prueba antes que nada `state replace-provider`. Resuelve el 90% de migraciones desde estados generados por versiones <0.13 sin tocar una sola línea de HCL. Solo si después aparecen errores de schema (atributo X no existe, tipo Y cambió) tendrás que recurrir a las técnicas de §7."

### 3.3 Limitaciones

- **No** convierte un provider en otro distinto (no sirve para migrar de `aws` a `awscc`, son recursos diferentes).
- **No** actualiza el HCL — hay que cambiar el bloque `required_providers` en paralelo.
- Requiere lock activo del state, igual que cualquier otra escritura.

---

## 4. Cross-state moves: dividir un state monolítico

Este es el escenario opuesto al [lab-11](../../labs/lab-11/README.md), que parte ya de un diseño en capas. Aquí tienes un state monolítico con `vpc`, `rds`, `eks` y `apps` (250+ recursos en un único `terraform.tfstate`) y necesitas romperlo en varios states independientes **sin destruir nada y sin downtime**.

### 4.1 Por qué dividir un monolito existente

| Problema del monolito | Síntoma observable |
|----------------------|--------------------|
| Blast radius enorme | Un `apply` mal hecho amenaza networking y compute a la vez |
| Tiempos de plan altos | `terraform plan` tarda 4+ minutos al refrescar 250 recursos |
| Locks que bloquean a todos | El equipo de apps no puede desplegar mientras networking está aplicando |
| Permisos IAM acoplados | Un solo rol tiene permisos sobre todo |
| Imposible delegar ownership | Nadie puede ser responsable de "su" capa |

### 4.2 Comando clave: `state mv -state-out`

```bash
# 1. En el monolito, hacer backup obligatorio
$ cd ~/repos/infra-monolito/
$ terraform state pull > backup-pre-split.$(date +%s).json

# 2. Crear un nuevo proyecto con su propio backend en otro directorio
$ mkdir ~/repos/infra-networking/
$ cd ~/repos/infra-networking/
$ cat > providers.tf <<EOF
terraform {
  backend "s3" {
    bucket       = "tfstate-empresa"
    key          = "networking/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
EOF
$ terraform init   # crea el state vacío

# 3. Volver al monolito y mover recursos al state externo
$ cd ~/repos/infra-monolito/
$ terraform state mv \
    -state-out=../infra-networking/terraform.tfstate \
    aws_vpc.main \
    aws_vpc.main

$ terraform state mv \
    -state-out=../infra-networking/terraform.tfstate \
    'aws_subnet.public[0]' \
    'aws_subnet.public[0]'

# ... repetir para cada recurso de la capa networking

# 4. Subir el state poblado al backend del nuevo proyecto
$ cd ~/repos/infra-networking/
$ terraform state push ../infra-monolito/terraform.tfstate
$ terraform plan   # debe mostrar "No changes"

# 5. En el monolito: el HCL todavía declara los recursos, hay que limpiarlo
$ cd ~/repos/infra-monolito/
# Opción A: borrar el HCL y añadir 'removed { destroy = false }' temporalmente
# Opción B: si el monolito ya no tiene HCL del recurso, el state está limpio
$ terraform plan   # debe mostrar "No changes"
```

### 4.3 Diagrama de flujo

```
┌──────────────────────────────────┐         ┌────────────────────────────┐
│  monolito/terraform.tfstate      │         │  networking/...tfstate     │
│  ┌─────────────────────────────┐ │         │  ┌──────────────────────┐  │
│  │ aws_vpc.main                │─┼──mv────►│  │ aws_vpc.main         │  │
│  │ aws_subnet.public[0..2]     │─┼──mv────►│  │ aws_subnet.public... │  │
│  │ aws_internet_gateway.igw    │─┼──mv────►│  │ aws_internet_gw.igw  │  │
│  │ aws_db_instance.prod        │ │         │  └──────────────────────┘  │
│  │ aws_eks_cluster.main        │ │         └────────────────────────────┘
│  │ ...                         │ │
│  └─────────────────────────────┘ │         ┌────────────────────────────┐
└──────────────────────────────────┘         │  database/terraform.tfstate│
                                             │  ┌──────────────────────┐  │
                                             │  │ aws_db_instance.prod │  │
                                             │  └──────────────────────┘  │
                                             └────────────────────────────┘
```

### 4.4 Resolver dependencias entre los nuevos states

Los recursos que migran a otro state pierden las referencias `resource.attr` que tenían dentro del monolito. La capa que los necesita pasa a leer mediante [`terraform_remote_state`](../modulo-03/07_estrategias_avanzadas.md):

```hcl
# En infra-database/main.tf — antes vivía dentro del monolito y leía aws_subnet.private[*].id directamente
data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = "tfstate-empresa"
    key    = "networking/terraform.tfstate"
    region = "us-east-1"
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "prod-db"
  subnet_ids = data.terraform_remote_state.networking.outputs.private_subnet_ids
}
```

Esto exige que el nuevo proyecto `networking/` declare en sus `outputs.tf` los valores que las otras capas van a consumir. Es la oportunidad para definir la **interfaz pública** de cada capa.

### 4.5 `state mv -state-out` vs `terraform_remote_state` vs reescribir

| Estrategia | Cuándo usarla | Coste | Riesgo |
|-----------|---------------|-------|--------|
| `state mv -state-out` | El recurso debe seguir gestionado, solo cambia de state file | Medio (manual, recurso a recurso) | Bajo si hay backup |
| `terraform_remote_state` | El recurso ya está en otro state y solo necesitas leerlo | Bajo | Muy bajo |
| Reescribir desde cero | El recurso es trivial de recrear y se puede reemplazar | Alto si hay datos | Muy alto si hay datos |
| `import` block en el destino + `removed { destroy = false }` en origen | Alternativa declarativa más nueva | Alto (un import por recurso) | Muy bajo, totalmente auditable |

> **En la práctica:** "Para 5-10 recursos, `state mv -state-out` es la herramienta correcta. Para 50+, considera la cuarta fila: `import` declarativo con `for_each` en el destino y `removed { destroy = false }` en el origen. Es más código, pero es revisable en PR y reproducible si te equivocas. El tiempo que pierdes escribiendo los bloques lo recuperas en la auditoría posterior."

---

## 5. Fusión inversa: consolidar dos states en uno

El caso espejo de §4. Aparece típicamente tras una fusión de equipos o tras decidir que dos pilas pequeñas tenían demasiado acoplamiento como para vivir separadas.

### 5.1 Comando con `-state` y `-state-out`

```bash
# Equipo A tiene tfstate-a; equipo B tiene tfstate-b
# Queremos consolidar todos los recursos de B en A

$ terraform state pull > tfstate-a.json   # desde el directorio de A
$ cd ../proyecto-b/
$ terraform state pull > tfstate-b.json

# Mover un recurso entre dos state files locales
$ terraform state mv \
    -state=tfstate-b.json \
    -state-out=../proyecto-a/tfstate-a.json \
    aws_security_group.web \
    aws_security_group.web_b   # renombrar para evitar colisión
```

### 5.2 Detección previa de colisiones

```bash
# Listar y combinar
$ (cd proyecto-a/ && terraform state list | sort) > a.list
$ (cd proyecto-b/ && terraform state list | sort) > b.list

# Recursos que colisionan por nombre
$ comm -12 a.list b.list
aws_security_group.web         # ← colisión: hay que renombrar
aws_iam_role.lambda_exec       # ← colisión: hay que renombrar
```

Para cada colisión, **renombrar antes** con un bloque `moved` en el HCL del proyecto B:

```hcl
# En proyecto-b/main.tf, antes de migrar
moved {
  from = aws_security_group.web
  to   = aws_security_group.web_b
}

resource "aws_security_group" "web_b" {  # antes era "web"
  # ...
}
```

Aplicar el `moved` en B, y solo entonces ejecutar `state mv` cross-state.

### 5.3 Verificación post-fusión

```bash
$ cd proyecto-a/
$ terraform state list | wc -l       # debe ser n_a + n_b - colisiones_renombradas
$ terraform plan                      # debe mostrar "No changes"
$ diff <(terraform state list | sort) <(cat ../tfstate-a.json | jq -r '.resources[].instances[] | .module + .type + .name' | sort)
```

> **Nota importante:** "La fusión inversa es la operación con más probabilidad de causar pérdida de información en todo este temario. Si te equivocas con `state mv -state-out` y mueves un recurso a un state que luego se sobrescribe, ese recurso desaparece del control de Terraform pero **sigue vivo en AWS** — y nadie sabrá que existe hasta el siguiente audit de costes. Antes de cada `state mv` cross-state, **dos backups**: el origen y el destino. Sin excepciones."

---

## 6. Recuperación de locks colgados — `force-unlock` con cabeza

`force-unlock` se enseña en una línea en el [Módulo 3 §3](../modulo-03/03_locking.md). En esta sección lo tratamos como un **procedimiento clínico**: el comando no es la primera respuesta, es la última.

### 6.1 Anatomía de un lock

**DynamoDB (legacy):**

```bash
$ aws dynamodb get-item \
    --table-name terraform-locks \
    --key '{"LockID":{"S":"tfstate-empresa/prod/terraform.tfstate-md5"}}'
{
  "Item": {
    "LockID":   {"S": "tfstate-empresa/prod/terraform.tfstate-md5"},
    "Info":     {"S": "{\"ID\":\"a1b2-...\",\"Operation\":\"OperationTypeApply\",\"Who\":\"alice@host.local\",\"Created\":\"2024-03-12T14:32:11Z\"}"}
  }
}
```

**Native S3 lockfile (Terraform 1.10+):**

```bash
$ aws s3 cp s3://tfstate-empresa/prod/terraform.tfstate.tflock - | jq
{
  "ID":        "a1b2c3d4-e5f6-7890",
  "Operation": "OperationTypeApply",
  "Who":       "alice@host.local",
  "Created":   "2024-03-12T14:32:11Z",
  "Path":      "tfstate-empresa/prod/terraform.tfstate"
}
```

### 6.2 Investigación obligatoria antes de forzar

| Pregunta | Cómo responderla | Por qué importa |
|----------|------------------|------------------|
| ¿Quién lanzó el apply? | Campo `Who` del lock | Es la persona que sabe qué estaba haciendo |
| ¿Sigue su proceso vivo? | Slack a esa persona; `ps -ef` en el runner CI; `aws ec2 describe-instances` | Si vive, **no fuerces** — espera o aborta tú |
| ¿Hay otro apply en paralelo? | `aws dynamodb scan` filtrando por `LockID` similar | Otro proceso podría reaplicar lo que tu apply dejó a medias |
| ¿Modificó recursos antes de morir? | `terraform plan` post-unlock — si hay drift, hubo apply parcial | Determina si necesitas reconciliación inmediata |
| ¿Cuándo se creó el lock? | Campo `Created` del lock | Locks de >24h casi siempre son huérfanos legítimos |

> **En la práctica:** "El error más caro que vi por un `force-unlock` precipitado: dos developers haciendo apply simultáneo sobre el mismo state desde rutas distintas (uno desde su laptop, otro desde el CI). El primero ganó el lock. El segundo lo forzó porque 'parecía colgado'. El primero terminó su apply, escribió el state. El segundo, ya con el lock falso, escribió encima un state desactualizado. Resultado: 14 recursos huérfanos en AWS, 3 horas para reconciliar manualmente. Tiempo que habría ahorrado un `slack @alice ¿estás aplicando?`"

### 6.3 Procedimiento seguro

```bash
# 1. Pull con bandera que ignora lock — solo lectura
$ terraform state pull > current-state.json   # esto NO requiere lock

# 2. Identificar el LockID (visible en el error de tu plan/apply)
$ terraform plan
Error: Error acquiring the state lock
  ID:        a1b2c3d4-e5f6-7890
  Path:      tfstate-empresa/prod/terraform.tfstate
  Operation: OperationTypeApply
  Who:       alice@host.local
  Created:   2024-03-12 14:32:11.234 +0000 UTC

# 3. Investigar (las cinco preguntas de §6.2)

# 4. Si y solo si confirmas que el lock es huérfano, forzar
$ terraform force-unlock a1b2c3d4-e5f6-7890

# 5. Auditoría posterior obligatoria
$ terraform plan   # ¿hay drift que no había antes?
```

### 6.4 Limpieza manual de un lockfile S3 colgado

En backends con `use_lockfile = true` (TF 1.10+), `terraform force-unlock` ya gestiona internamente el borrado del objeto `.tflock` en S3 — no es necesario tocarlo a mano en condiciones normales. La limpieza manual solo aplica como **último recurso** cuando `force-unlock` no puede completar la operación: por ejemplo, si los permisos IAM `s3:DeleteObject` sobre la key del lockfile no están concedidos al rol que ejecuta el comando, o si el lockfile quedó huérfano por un bug puntual del backend.

```bash
$ aws s3api delete-object \
    --bucket tfstate-empresa \
    --key prod/terraform.tfstate.tflock

# Solo si puedes confirmar inequívocamente que ningún proceso Terraform
# está usándolo en este momento. Esta operación no tiene undo.
```

> **Permisos IAM requeridos** (documentación oficial del backend S3): cuando `use_lockfile = true`, el rol que ejecuta `terraform` necesita `s3:GetObject`, `s3:PutObject` y `s3:DeleteObject` sobre la key específica del lockfile (`<key>.tflock`). Es un permiso adicional al `s3:DeleteObject` sobre el state — Terraform **no** borra el objeto del state, pero sí el del lockfile al terminar la operación.

### 6.5 Prevención: locks que expiran solos

DynamoDB no tiene TTL nativo para locks. Estrategias de mitigación:

- Configurar **CloudWatch Alarms** sobre la antigüedad del item — alertar cuando un lock supera 30 minutos.
- En CI/CD, añadir un `trap` que libere el lock si el job es cancelado:
  ```bash
  trap 'terraform force-unlock -force ${LOCK_ID:-}' EXIT
  ```
- HCP Terraform y Terraform Cloud tienen liberación automática tras N minutos de inactividad — una razón más para considerar el backend SaaS en equipos grandes.

---

## 7. State corrupto: schema mismatch y desincronización

### 7.1 Síntomas típicos

```
Error: Failed to read state file
  schema version 5 of resource is greater than current 4

Error: Resource instance managed by newer provider version
  The current state of "aws_db_instance.prod" was created by a
  newer provider version than is currently selected.

Error: Invalid resource state found
  An attribute value has unexpected type
```

### 7.2 Causas

| Causa | Cómo se produce |
|-------|-----------------|
| Downgrade del provider | El equipo bajó `version = "~> 5.30"` a `version = "~> 4.65"` sin migrar |
| Edición manual del state | Alguien tocó `terraform.tfstate` con un editor |
| Fork de provider con schema incompatible | Un mirror corporativo se quedó atrás respecto a upstream |
| Apply parcial corrupto | Terraform fue interrumpido mid-write (raro pero ocurre) |
| Versiones distintas en CI vs local | Equipo desarrolla con 1.7, CI ejecuta con 1.5 |

### 7.3 Diagnóstico controlado

```bash
# Pull a un fichero local
$ terraform state pull > broken.json

# Inspeccionar la cabecera
$ jq '{version, terraform_version, lineage, serial}' broken.json

# Ver qué provider y qué schema_version usa cada recurso
$ jq '.resources[] | {addr: (.module + "." + .type + "." + .name), provider: .provider, schema_version: .instances[0].schema_version}' broken.json
```

### 7.4 Reparaciones por orden de seguridad

**Paso 1 — Volver al provider correcto (siempre antes de tocar el state):**

```hcl
# providers.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.42.0"   # pin estricto a la versión que escribió el state
    }
  }
}
```

```bash
$ rm -rf .terraform .terraform.lock.hcl
$ terraform init
$ terraform plan
```

En el 70% de los casos, esto resuelve el error sin tocar el state.

**Paso 2 — Si el provider correcto no se puede instalar (deprecated, retirado), forzar refresh con el nuevo:**

```bash
$ terraform apply -refresh-only
# Terraform reescribe el state con el schema actual
# Validar que plan posterior es limpio
$ terraform plan   # esperado: No changes
```

**Paso 3 — Caso extremo: regenerar la entrada con `state rm` + `import`:**

```bash
# Solo si paso 1 y 2 fallan
$ terraform state rm aws_db_instance.prod
$ cat > imports.tf <<EOF
import {
  to = aws_db_instance.prod
  id = "prod-db"
}
EOF
$ terraform plan -generate-config-out=regenerated.tf
$ terraform apply
```

> **Nota importante:** "El paso 3 borra la entrada del state; si entre ese `state rm` y el `import` fallido alguien lanza un `apply` desde otro lado, Terraform creará un recurso nuevo encima del existente. Para operaciones del paso 3, **bloquea el backend manualmente** (revoca temporalmente los permisos IAM de los demás roles) durante la ventana."

### 7.5 Detección preventiva

```hcl
# En el módulo de CI, añadir validación de la versión del provider
resource "null_resource" "version_pin" {
  triggers = {
    expected = "5.42.0"
    actual   = data.external.aws_provider_version.result.version
  }
  lifecycle {
    precondition {
      condition     = data.external.aws_provider_version.result.version == "5.42.0"
      error_message = "Provider AWS debe ser exactamente 5.42.0 (state actual escrito con esa versión)"
    }
  }
}
```

Y, sobre todo, mantener el `.terraform.lock.hcl` versionado en Git con commits que requieran approval.

---

## 8. State surgery: cuándo `state push` es legítimo

El [Módulo 3 §5](../modulo-03/05_comandos_state.md) advierte sobre `terraform state push` con razón. Pero "no usarlo nunca" no es realista — hay tres escenarios donde es la herramienta correcta.

### 8.1 Los tres usos legítimos

**Caso 1 — Restauración tras DR.** Cubierto en [lab-12](../../labs/lab-12/README.md). El bucket S3 versionado guarda copias del state; tras una corrupción, restauras la versión sana con `aws s3api copy-object`. Eso es funcionalmente equivalente a un `state push` y se considera legítimo.

**Caso 2 — Aplicar un state reparado fuera de línea.** Cuando los pasos de §7.4 no resuelven el problema y necesitas editar el state con `jq` para corregir algo muy específico:

```bash
# Ejemplo: un recurso quedó con un atributo mal formateado tras un crash
$ terraform state pull > broken.json
$ jq '(.resources[] | select(.type == "aws_instance" and .name == "web") .instances[0].attributes.tags) |= (. // {})' broken.json > fixed.json

# Validar que solo cambió lo que querías
$ diff <(jq -S . broken.json) <(jq -S . fixed.json)

# Aumentar serial manualmente (importante)
$ jq '.serial += 1' fixed.json > final.json

# Push
$ terraform state push final.json
```

**Caso 3 — Migración de backend offline.** Cuando `init -migrate-state` no es viable porque los backends usan KMS keys distintas, residen en cuentas que no se pueden encadenar con AssumeRole, o el destino aún no existe en el momento del pull:

```bash
$ terraform state pull > pulled.json   # cuenta origen
# ... cambiar credenciales a cuenta destino, configurar nuevo backend ...
$ terraform init                        # crea backend vacío en destino
$ terraform state push pulled.json      # importa el state
```

### 8.2 Procedimiento ceremonial

`terraform state push` aplica **dos comprobaciones de seguridad** que conviene conocer (documentación oficial):

1. **Lineage matching**: si el `lineage` del state que subes no coincide con el del state remoto, Terraform rechaza el push. Esto evita pisar accidentalmente un state ajeno.
2. **Serial check**: si el `serial` remoto es **mayor** que el del state que subes, Terraform rechaza el push. El serial remoto mayor indica que hay cambios en destino que tu copia local no incorpora.

Ambas comprobaciones se pueden saltar con `-force`, pero **es justo lo que casi nunca debes hacer**. El procedimiento limpio incrementa el serial manualmente para superar el segundo check, conservando el lineage:

```bash
# 1. Bloqueo manual del backend
#    Revocar temporalmente la policy IAM que permite escribir el state
#    a roles distintos del tuyo. Volver a habilitar al final.

# 2. Backup
$ terraform state pull > backup.$(date +%s).json

# 3. Operación de cirugía sobre una copia
$ cp backup.<ts>.json surgery.json
$ # ... edición controlada con jq ...

# 4. Validación pre-push (lineage debe coincidir)
$ terraform state pull > current.json
$ diff <(jq -r '.lineage' current.json) <(jq -r '.lineage' surgery.json)
# Esperado: ambos lineage idénticos
$ diff <(jq -S '.resources | length' current.json) <(jq -S '.resources | length' surgery.json)
# Verificar que el count de recursos es coherente

# 5. Incremento de serial (necesario: el serial debe ser >= remoto)
$ jq '.serial = (.serial + 1)' surgery.json > push-ready.json

# 6. Push (sin -force; deja activas las protecciones de lineage/serial)
$ terraform state push push-ready.json

# 7. Validación post-push
$ terraform plan   # debe mostrar No changes (o el cambio esperado)

# 8. Restablecer permisos IAM
```

> **Nota importante:** "Hay tres comandos en Terraform que pueden destruir tu producción en cinco segundos: `state push`, `apply -auto-approve` sobre el plan equivocado, y `destroy` sin filtro. Los tres tienen su lugar — pero solo si los ejecutas con la misma ceremonia con la que un cirujano pide instrumental antes de operar. Si te encuentras tecleando `state push` con prisa, **para**. Tómate los 30 minutos que cuesta el procedimiento de §8.2. Tu yo de mañana te lo agradecerá."

---

## 9. Migración cero-downtime entre backends

Migrar de un backend a otro en un equipo de una persona es trivial: `terraform init -migrate-state`. En un equipo de quince personas con CI/CD activo y consumidores de `terraform_remote_state`, el ejercicio es muy diferente.

### 9.1 Plan de coordinación

```
Día -7   Anuncio: "Migración del state de prod-vpc el día X"
Día -3   Recordatorio + ventana de freeze (no merges en infra-prod-vpc)
Día -1   Bloqueo manual: revocar IAM:s3:PutObject sobre el state actual
Día 0    Migración (ventana de 30 min)
Día 0+1h Anuncio de éxito + ventana de freeze levantada
Día +7   Backup post-migración archivado a Glacier con TTL de 90 días
```

### 9.2 Estrategias por escenario

| Escenario | Estrategia | Por qué |
|-----------|-----------|---------|
| S3 → S3 misma región, mismo cifrado | `init -migrate-state` | Caso simple, una transacción |
| S3 → S3 cross-account | Pull/push manual con `assume-role` entre medias | `migrate-state` no soporta cambio de credenciales mid-flight |
| S3 → S3 con KMS keys distintas | Pull/push manual; descifra con KMS A, cifra con KMS B | El backend solo conoce una KMS por config |
| S3 → HCP Terraform | Pull manual + import en HCP | HCP no acepta `init -migrate-state` directo desde algunos backends |
| S3 → Azure Blob / GCS | Pull/push manual | Cambio de provider del backend |

### 9.3 Procedimiento `init -migrate-state` (caso simple)

```hcl
# providers.tf — antes
terraform {
  backend "s3" {
    bucket = "tfstate-old"
    key    = "prod/terraform.tfstate"
    region = "us-east-1"
  }
}

# providers.tf — después
terraform {
  backend "s3" {
    bucket = "tfstate-new"
    key    = "prod/terraform.tfstate"
    region = "us-east-1"
  }
}
```

```bash
$ terraform init -migrate-state
Initializing the backend...
Backend configuration changed!

Do you want to copy existing state to the new backend?
  Pre-existing state was found while migrating the previous "s3" backend
  to the newly configured "s3" backend. ...
  Enter "yes" to copy and "no" to start with an empty state.

  Enter a value: yes

Successfully configured the backend "s3"!
```

### 9.4 Procedimiento manual (escenarios complejos)

```bash
# 1. Anuncio + freeze (ya hecho en día -3)

# 2. Lock manual: revocar PutObject sobre el state actual
$ aws s3api put-bucket-policy --bucket tfstate-old --policy file://deny-write.json

# 3. Pull
$ terraform state pull > migration.$(date +%s).json

# 4. Cambiar credenciales / asumir rol de la cuenta destino
$ export AWS_PROFILE=cuenta-destino

# 5. Apuntar el HCL al nuevo backend, init sin migrate
$ terraform init   # crea state vacío en destino

# 6. Push
$ terraform state push migration.<ts>.json

# 7. Validación
$ terraform plan   # esperado: No changes

# 8. Hash check (opcional pero recomendado)
$ aws s3api get-object --bucket tfstate-new --key prod/terraform.tfstate hash-test.json
$ diff <(jq -S 'del(.serial)' migration.<ts>.json) <(jq -S 'del(.serial)' hash-test.json)
# Solo el serial debería diferir

# 9. Restablecer permisos en el viejo bucket (opcional: dejarlo solo-lectura permanente)

# 10. Anuncio de éxito
```

### 9.5 Verificación de consumidores

Si otros proyectos leían el state migrado vía `terraform_remote_state`, hay que actualizar **todos** sus configs antes de que se ejecute su próximo apply:

```bash
# Auditar consumidores
$ grep -rn 'bucket\s*=\s*"tfstate-old"' /repos/*/

# Actualizarlos en PRs paralelos
# Mergear todos antes de levantar el freeze
```

---

## 10. Checklist de migración auditable

Toda operación de cirugía de state, sea cual sea, sigue la misma ceremonia. Imprime esta lista, pégala junto al monitor, y cúmplela sin atajos.

```markdown
Pre-migración
  [ ] Backup del state origen     terraform state pull > backup-origen.<ts>.json
  [ ] Backup del state destino    terraform state pull > backup-destino.<ts>.json (si aplica)
  [ ] terraform plan en origen    debe ser "No changes"
  [ ] terraform plan en destino   debe ser "No changes" (si aplica)
  [ ] Anuncio comunicado a equipos consumidores
  [ ] Freeze de PRs en repos afectados
  [ ] Permisos verificados en backend destino (write access del runner)
  [ ] Permisos verificados en backend origen (revocar write a terceros durante la ventana)
  [ ] Plan de rollback escrito y validado

Durante
  [ ] Lock explícito en el backend de origen (o bloqueo manual de IAM)
  [ ] Operación de migración en una sola transacción lógica
  [ ] Verificación: terraform state list | wc -l antes y después coincide (ajustando por moves)
  [ ] Si edición manual: jq diff entre origen y resultado solo muestra cambios esperados

Post-migración
  [ ] terraform plan en el destino: 0 cambios (o el cambio esperado y solo ese)
  [ ] terraform plan en el origen (si todavía existe): 0 cambios
  [ ] Smoke test sobre 3-5 recursos críticos (terraform state show <recurso>)
  [ ] Backup post-migración archivado a Glacier con TTL >= 90 días
  [ ] Lineage del state nuevo coincide con el de origen (jq '.lineage')
  [ ] ADR firmado en el repo: decisión, procedimiento aplicado, hash de los backups
  [ ] Anuncio de éxito a los equipos
  [ ] Freeze levantado
```

> **En la práctica:** "Esta lista no es un checklist de oficina — es la diferencia entre 'migración exitosa' y 'incidente que llega al post-mortem'. Cada casilla tiene una historia detrás de alguien que se la saltó."

---

## Resumen y siguiente paso

Has aprendido a operar sobre el state cuando las herramientas declarativas no bastan: migración entre versiones de Terraform/OpenTofu, cambio de namespace de provider, cross-state moves, fusiones, recuperación de locks colgados, reparación de schemas, cirugía con `state push` y migraciones de backend cero-downtime — todas con la misma ceremonia: backup, lock, operación, verificación, ADR.

La sección §6 cierra el módulo con la última pieza del Terraform avanzado: rendimiento y escala. Verás cómo medir y optimizar `terraform plan` y `apply` en proyectos con cientos de recursos, donde cada segundo de espera del CI es un coste real para el equipo.

---

> [← Volver al índice](./README.md) | [Siguiente →](./06_rendimiento_escala.md)
