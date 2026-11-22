# Guía: recuperar un nodo, ponerlo al día y entregarlo al Integrante 2

Procedimiento reproducible para obtener una instancia `pg-recovery` **operativa, con datos
preservados, esquema actualizado, registro de ids íntegro, secuencia válida y mecanismo
anti-duplicados activo**. Todos los comandos se ejecutan desde la raíz del proyecto en el host.
La reincorporación a la replicación es del Integrante 2 y no forma parte de esta guía.

> Regla: una instancia recuperada **no** se entrega ni recibe escrituras hasta que
> `make recovery-status` termine con código 0 y la línea "apta para entregar".

## 1. Recuperar (PITR)

Demostración completa automatizada (respaldo, cambios A/B, falla, PITR, migración, validación):

```bash
make pitr-demo NODE=san_carlos
# si ya existe una recuperación previa y se puede descartar:
scripts/recovery/pitr_demo.sh san_carlos --reset
```

Manual, desde un respaldo físico existente (`make backup-list`):

```bash
RECOVERY_SOURCE_NODE=san_carlos \
RECOVERY_BASEBACKUP=/backups/physical/san_carlos/<FECHA>/data \
RECOVERY_TARGET_TIME='2026-11-20 17:29:00+00' \
docker compose --profile recovery up -d pg-recovery
docker compose --profile recovery logs pg-recovery | grep -E 'recovery stopping|selected new timeline|archive recovery complete'
```

`sigtec-recovery-entrypoint` solo prepara la recuperación si el volumen está vacío. Para otro
intento: `make recovery-clean` (pide escribir `ELIMINAR`; elimina **solo** `pg-recovery`).

### Si la copia base proviene de una instancia ya recuperada

Su `postgresql.auto.conf` puede conservar el objetivo del PITR anterior. La nueva recuperación
falla con `recovery ended before configured recovery target was reached` o
`multiple recovery targets specified`. Desde esta corrección `pitr_demo.sh` retira esos
parámetros al promover (`ALTER SYSTEM RESET`), pero una copia antigua puede tenerlos:

1. Haga una **copia** del respaldo (no modifique el original).
2. En la copia, elimine de `data/postgresql.auto.conf` las líneas `recovery_target*`,
   `restore_command` y el comentario `# --- SIG-TEC: recuperación PITR`.
3. Recupere con un objetivo explícito, p. ej. `RECOVERY_TARGET_LSN` = `End-LSN` de
   `data/backup_manifest`.

`remediation/RA-01/scripts/clone_recovery_into_lab.sh` automatiza estos pasos para un laboratorio.

## 2. Esperar la promoción

```bash
make psql NODE=recovery        # SELECT pg_is_in_recovery();  -> f
```

Si devuelve `t`, la instancia sigue reproduciendo WAL o está en pausa. `make migrate NODE=recovery`
se niega a continuar (código 4) hasta que esté promovida.

## 3. Aplicar las migraciones posteriores al instante restaurado

Recuperar un instante anterior a una migración restaura también el esquema anterior. Un nodo
recuperado anterior a `0103` acepta el mismo id en dos capas (RA-01).

```bash
make migrate NODE=recovery
```

El comando hace, en orden, y se detiene con código ≠ 0 ante cualquier fallo:

| Paso | Qué comprueba / hace | Código si falla |
|---|---|---|
| Destino | `recovery` se acepta solo si se nombra; un nombre desconocido es un error | 2 |
| Existencia y conexión | `pg-recovery` resuelve, acepta conexiones y credenciales | 3 |
| Promoción | `pg_is_in_recovery() = false` | 4 |
| Identidad | `ops.node_info` (nodo, `campus_id`, esquema) coherente con el catálogo y con `SIGTEC_RECOVERY_INFO`; nunca se usa la identidad del nodo en servicio y no se reescribe | 4 |
| Inspección | migraciones registradas y pendientes, objetos por capa, disparadores, secuencia, registro, **ids repetidos entre capas** | 5 si hay repetidos (no se modifica nada) |
| Respaldo previo | `pg_dump` validado (TOC, lectura completa, ocho capas) en `/backups/recovery_pre_migracion/<UTC>/` | 1 |
| Migraciones | cada una en una sola transacción, registrada con su SHA-256 | 1 (la fallida se revierte completa) |
| Verificación posterior | ninguna pendiente + `sql/checks/verificar_0103.sql`: registro y PK, ids únicos y registrados, campus y formato, 24 disparadores habilitados, modos de seguridad, permisos de mantenimiento, secuencia ≥ máximo usado, siguiente id libre | 1 |

Repetirlo es seguro: sin pendientes no reaplica nada ni toma otro respaldo.

### Si informa ids repetidos (código 5)

El comando lista los ids y capas (`ids repetidos entre capas: 3000000083 en iluminacion+puntos_interes`).
**No borra ni renumera.** Decida qué objeto conserva el id (ver
[docs/BACKUP_RECOVERY.md](../../docs/BACKUP_RECOVERY.md), "Conflictos de identificadores"),
reinserte el otro sin `id` desde `make psql NODE=recovery` y repita `make migrate NODE=recovery`.

## 4. Validar

```bash
make recovery-status          # código 0 y "apta para entregar al Integrante 2"
```

Incluye versiones, migraciones pendientes (debe decir "todas aplicadas"), validación de las
ocho capas, `verificar_registro_ids.sql` (`estado_ids = OK`) y `verificar_0103.sql` (10 PASS).
Con algo pendiente o fallido imprime `NO APTA` y devuelve 1.

## 5. Ajustar la secuencia frente a los ids que el central ya conoce

Solo si el central (Integrante 2) tiene ids de ese campus mayores que los recuperados:

```bash
docker compose --profile tools run --rm -T sigtec-tools -c '. scripts/lib/db.sh
  psql_su recovery -v schema=local_san_carlos -v campus_id=3 -v max_id=<MÁXIMO_ID_EN_EL_CENTRAL> \
    -f sql/templates/ajustar_secuencia_tras_recuperacion.sql'
```

Debe ejecutarse **después** del paso 3 (consulta el registro). Nunca retrocede la secuencia.

## 6. Entregar al Integrante 2

| Dato | Valor |
|---|---|
| Servicio / puerto | `pg-recovery`, `127.0.0.1:55436`, base `sigtec` |
| Identidad | la del campus restaurado (`ops.node_info`), p. ej. `san_carlos`, `campus_id 3` |
| Estado exigido | `make recovery-status` = apta (código 0) |
| Garantías | registro `ops.identificadores_globales` íntegro; 24 disparadores; ids explícitos solo para `sigtec_mantenimiento_id`; ids eliminados no reutilizables |
| Respaldo previo a la migración | `/backups/recovery_pre_migracion/<UTC>/` |
| Pendiente (I2) | ranuras, publicación y suscripción; reconciliar objetos posteriores al instante objetivo; **no demostrado** |

## 7. Comprobación automática

`make test` incluye:

* `[2b] tests/container/test_recovery_migracion.sh`: PITR real en clústeres temporales hacia un
  instante anterior a 0103 → promoción → migración → validación → ataques → reinicio, y todos los
  códigos de error.
* `[2c]`: si `pg-recovery` está en ejecución, `verify.sh recovery` debe declararla apta.
