# F-01 — Falso éxito de respaldo: causa y corrección

## 1. Reproducción antes de la corrección

`remediation/scripts/reproduce_audit_defects.sh` contra el laboratorio aislado `sigtec_remed`
(puertos 57430–57436), con `SIGTEC_BACKUP_PASSWORD` incorrecta y `BACKUP_ROOT` temporal.
Evidencia: [evidence/01_reproduccion_prefix/reproduce_audit_defects.log](evidence/01_reproduccion_prefix/reproduce_audit_defects.log).

| Caso | Resultado observado |
|---|---|
| `logical_backup.sh central` | `OK central: 0 bytes, 0 entradas TOC`, código **0**, 1 directorio publicado |
| `physical_backup.sh central` | `OK central: 0 MiB, inicio ` (vacío), código **0**, 1 directorio publicado |

## 2. Causa raíz

`backup_node` se invocaba como `if ! ( set -Eeuo pipefail; backup_node "$node" ); then …`.
En Bash, **`errexit` se ignora en toda función o subshell evaluado en un contexto condicional**
(`if`, `!`, `||`, `&&`), aunque el subshell ejecute `set -e` por su cuenta. Por eso:

1. `pg_dump` / `pg_basebackup` fallaba con autenticación inválida.
2. La ejecución continuaba: se calculaban tamaño y SHA-256 del archivo vacío, se escribía el
   manifiesto, se registraba `OK` en `backup_log.tsv`.
3. La última instrucción terminaba con éxito → el subshell devolvía 0 → el script terminaba con 0.
4. El directorio ya tenía su nombre definitivo (`<nodo>/<UTC>`), de modo que `latest_dir`,
   `restore-test` y el PITR podían elegir una copia vacía.

## 3. Corrección

| Archivo | Cambio |
|---|---|
| `scripts/lib/db.sh` | `run_step`: ejecuta la función en un subshell con `set -Eeuo pipefail` **como instrucción simple** (no condicional) y deja el código en `RUN_RC`. `psql_backup` usa `-w` (nunca pide contraseña). |
| `scripts/lib/backup.sh` | `fail`, `show_diag` (muestra stderr de PostgreSQL sangrado, sin secretos), `work_dir_for` (`.en-curso-<UTC>-<pid>`), `publish_dir` (`mv -T` atómico), `discard_work_dir` (borra la carga útil y renombra a `.fallido-…`), `validate_logical_dir`, `validate_physical_dir`, `backup_log_safe`. |
| `scripts/backup/logical_backup.sh` | Cada comando crítico se comprueba explícitamente (`|| { show_diag; fail …; }`), además de `trap ERR`. Orden: copia → validación → manifiesto → publicación → `OK`. Bucle con `run_step`; un nodo fallido marca `ERROR` y el script termina con 1. |
| `scripts/backup/physical_backup.sh` | Igual, con `pg_basebackup --no-password` y validación física. |
| `scripts/backup/*_restore_test.sh` | Bucle con `run_step`; un nodo fallido ya no se pierde dentro de un `if`. |
| `Makefile` | Sin cambios en `backup`: ya encadenaba con `&&`; ahora recibe un código ≠ 0 real y se detiene. |

### Validación antes de publicar

* **Lógica:** `pg_restore --list` (TOC legible) → `pg_restore --file=/dev/null` (lee todos los
  bloques: detecta truncamiento) → el TOC contiene la extensión PostGIS, `ops.node_info` y los
  datos de las ocho capas del campus → `globals.sql` contiene `CREATE ROLE`.
* **Física:** `PG_VERSION` = 17, `backup_label` con `START WAL LOCATION`, `backup_manifest`,
  `global/pg_control` y `pg_verifybackup` ("backup successfully verified").
* La restauración completa se mantiene como prueba periódica (`make restore-test`), sin cambios
  en su alcance.

### Directorios

| Estado | Nombre | Visible para `latest_dir`, restauración, PITR y retención |
|---|---|---|
| En curso | `<nodo>/.en-curso-<UTC>-<pid>/` | No |
| Fallido | `<nodo>/.fallido-<UTC>-<pid>/` (solo `*.stderr`, sin carga útil) | No |
| Publicado | `<nodo>/<UTC>/` | Sí |

Si `<UTC>` ya existe (dos respaldos en el mismo segundo), se publica como `<UTC>-<pid>`: nunca
se sobrescribe un respaldo anterior.

## 4. Pruebas nuevas

`tests/container/test_backup_failures.sh` (incluida en `make test`, sección `[2b]`), 36 casos,
escribe en un `BACKUP_ROOT` bajo `/tmp` del contenedor efímero (no toca el volumen de respaldos):

| Grupo | Casos |
|---|---|
| Negativos (lógico y físico) | contraseña incorrecta en los seis nodos · diagnóstico visible sin la contraseña · usuario inexistente · servidor inaccesible · destino de solo lectura · directorio inválido · escritura interrumpida (`ulimit -f`) sin carga útil residual · código preservado a través de un pipeline |
| Positivos | respaldo de los seis nodos + validación + restauración aislada (lógico y físico) · un fallo posterior conserva el respaldo válido anterior · fallo parcial (un nodo bien, otro mal → código 1, solo el bueno publicado) |
| Artefactos dañados | dump truncado rechazado · copia física alterada rechazada por `pg_verifybackup` · copia sin `backup_manifest` rechazada |

`remediation/scripts/test_backup_host_paths.sh` (10 casos) cubre las rutas del anfitrión
(`make backup-logical`, `make backup-physical`, `make backup`): con la contraseña del central
desincronizada devuelven código 2, `make backup` se detiene antes de la etapa física y no se
publica nada; tras `make migrate` (resincroniza) `make backup` vuelve a funcionar.

## 5. Resultados

| Ejecución | Resultado | Evidencia |
|---|---|---|
| Reproducción tras la corrección (laboratorio) | lógico rc=1, publicados=0; físico rc=1, publicados=0 | [04](evidence/04_reproduccion_postfix/reproduce_audit_defects.log), [10](evidence/10_reproduccion_final/reproduce_audit_defects.log) |
| `test_backup_failures.sh` (laboratorio) | 36 PASS, 0 FAIL | [02](evidence/02_respaldos/lab_test_backup_failures.log) |
| `test_backup_host_paths.sh` (laboratorio) | 10 PASS, 0 FAIL | [02](evidence/02_respaldos/lab_test_backup_host_paths.log) |
| Instalación limpia del laboratorio: `make backup` + `make restore-test` | 6 VÁLIDA + 6 RECUPERABLE | [06](evidence/06_lab_instalacion_limpia/pipeline.log) |
| Originales antes de migrar | 6 lógicos validados + 6 físicos verificados; 6 VÁLIDA + 6 RECUPERABLE | [07](evidence/07_original_pre_migracion/pipeline.log) |
| Originales después de migrar | 36 PASS en la suite; 6 VÁLIDA + 6 RECUPERABLE | [09](evidence/09_original_post_migracion/pipeline.log) |

Mensaje de diagnóstico tras la corrección (extracto real, la contraseña nunca aparece):

```
      | pg_dump: error: connection to server at "pg-central" (…), port 5432 failed: FATAL:  password authentication failed for user "sigtec_backup"
  FALLA: pg_dump terminó con error
  ERROR respaldando central: no se publicó ningún respaldo
RESULTADO: uno o más respaldos lógicos FALLARON
```

## 6. Correcciones relacionadas (no bloqueantes)

| Hallazgo | Cambio | Verificación |
|---|---|---|
| F-03 marca RECUPERADA | `pitr_steps.sh marcar-recuperada` pasa variables por stdin (se interpolan) y exige `count = 1`; `pitr_demo.sh` propaga el código de cada paso, exige ≥ 6 PASS, comprueba en PostgreSQL `A < objetivo < B`, la marca y el estado del nodo original | PITR EXITOSA en el laboratorio limpio ([06](evidence/06_lab_instalacion_limpia/pitr/pitr_20261120T212428Z.md)) |
| F-04 puertos | `check_prereqs.sh` lee `SIGTEC_PORT_*` de `.env` (o `.env.example`) | `[OK] puertos libres: 57430 … (de .env)` sin variables exportadas ([06](evidence/06_lab_instalacion_limpia/pipeline.log)); antes rc=1 ([00](evidence/00_baseline/lab_prefix_setup.log)) |
| F-05 `APPLY=0` | `make wal-retention`: `""`/`0` simula, `1` aplica, otro valor → error 2 | `make wal-retention` en el laboratorio: "Simulación: no se eliminó nada" |
