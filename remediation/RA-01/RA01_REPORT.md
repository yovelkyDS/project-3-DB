# RA-01 — Informe de corrección

Defecto: **RA-01 (ALTO)** de la segunda auditoría (`audit/reaudit/FINDINGS.md`). El nodo
`pg-recovery` original conservaba el modelo anterior a la migración 0103, así que en él seguía
abierto F-02. Además, la ruta de actualización indicada devolvía éxito sin migrar.

Alcance: solo RA-01. No se tocaron Dockerfiles, imágenes, el modelo geográfico, las migraciones
0101–0103, la replicación ni `audit/`. Siguen abiertos F-06, F-07 y F-09, que no bloquean.

## 1. Causa raíz (confirmada en el código)

| # | Ubicación anterior | Causa | Efecto |
|---|---|---|---|
| 1 | `scripts/db/migrate.sh:64` `for node in $(nodes_expand "${@:-all}")` | Una sustitución de comando que se usa como lista de un `for` descarta su código de salida. `set -e` no actúa: el `for` recibe una lista vacía y el script termina con 0. | `migrate.sh recovery` y `make migrate NODE=recovery` imprimían `nodo inválido: recovery` y devolvían **0** |
| 2 | `scripts/lib/nodes.sh:90–101`, `node_valid` | El catálogo solo contiene los seis nodos en servicio. `recovery` es un destino físico (`target_host`), no una identidad lógica. | `migrate.sh` no tenía forma de dirigirse a la instancia recuperada |
| 3 | Bash sin `inherit_errexit` | Dentro de `$(…)` Bash desactiva `set -e`. Un fallo intermedio en una función que se llama por sustitución no detenía nada. | Posibles éxitos falsos aunque se arreglara el `for` |
| 4 | `migrate.sh` en general | No separaba destino físico de identidad lógica. Migrar la copia exige tomar `campus_id` y esquema **de la propia copia**, sin reescribir `ops.node_info` con los datos del nodo en servicio. | Apuntar a `NODE=san_carlos` actualiza el campus activo, no la copia |
| 5 | `scripts/db/verify.sh` | Si faltaba el registro solo informaba (código 0). | `make recovery-status` aceptaba la copia vulnerable |
| 6 | `remediation/INTEGRATION_IMPACT.md:37–39`, `GLOBAL_ID_FIX.md:115` | Remitían a `make migrate`, que no incluye `pg-recovery`. | La guía conducía al éxito falso |
| 7 | `sql/templates/ajustar_secuencia_tras_recuperacion.sql:22` | Desde 0103 consulta `ops.identificadores_globales`. | Ajustar la secuencia no puede sustituir la migración; debe ir después |

Reproducción antes de la corrección, sobre un clon de laboratorio del `pg-recovery` original
(`evidence/02_reproduccion_antes/reproduce_ra01.log`):

* **RA-01a, reproducido.** `make migrate NODE=recovery` devolvió 0 y no aplicó 0103.
* **RA-01b, reproducido.** Dos conexiones de un editor sin privilegio sobre la secuencia confirmaron
  `3000000083` en dos capas.

## 2. Corrección

### `scripts/db/migrate.sh` (reescrito)

* **Destinos.** `expand_targets` acepta `recovery` solo si se nombra. La lista se obtiene en una
  asignación (`targets="$(expand_targets …)" || fail … 2`), no dentro del `for`. Se activa
  `shopt -s inherit_errexit`. `all` y `campus` siguen siendo los nodos en servicio. Si `all` deja
  fuera una `pg-recovery` atrasada, se imprime un AVISO.
* **Comprobaciones previas:**
  * El nombre resuelve, `pg_isready` responde y `SELECT 1` autentica. Si no, código **3**, con la
    línea FATAL del servidor y nunca la contraseña.
  * Para `recovery`, además:
    * debe estar promovida: `pg_is_in_recovery() = f`, si no código **4**;
    * su identidad se lee de la copia (`ops.node_info`) y debe concordar con el catálogo, el esquema
      existente y el `source_node` de `SIGTEC_RECOVERY_INFO`, si no código **4**.
* **Inspección (`inspect_recovery`).** Registra:
  * migraciones registradas y pendientes;
  * objetos por capa;
  * disparadores habilitados;
  * secuencia y consecutivo máximo;
  * presencia del registro;
  * **ids repetidos entre capas**: si los hay, lista id y capas, termina con código **5** y no
    modifica nada.
* **Respaldo previo (`backup_recovery`).** Solo si hay migraciones pendientes:
  * `pg_dump` en `$BACKUP_ROOT/recovery_pre_migracion/<UTC>/`;
  * se valida el TOC, una lectura completa, las ocho capas y `ops.node_info`;
  * se publica con `mv -T` atómico;
  * si algo falla, código 1.
* **Aplicación.** Cada migración se aplica con `--single-transaction` y se registra con su SHA-256.
  Cualquier error SQL o de permisos da código **1**, y la migración se revierte entera.
  `ops.node_info` no se reescribe para `recovery`.
* **Verificación posterior (`post_check`).** No deben quedar pendientes y
  `sql/checks/verificar_0103.sql` debe dar 10 PASS y ningún FAIL; si no, código **1**.
* **Trampa `EXIT`.** Si el código no es 0 imprime `RESULTADO: migración FALLIDA en <destino>
  (código N)`.

### `sql/checks/verificar_0103.sql` (nuevo, solo lectura)

Diez comprobaciones con formato `PASS|FAIL|nombre|detalle`:

* 0103 registrada;
* `PRIMARY KEY (id)` del registro;
* ids únicos entre las ocho capas;
* todos los objetos registrados con su capa;
* campus y formato;
* 24 disparadores habilitados;
* modos de seguridad (`tg_asignar_identificador` INVOKER; las otras tres DEFINER con
  `search_path=pg_catalog, pg_temp`);
* permisos de mantenimiento (rol NOLOGIN, `EXECUTE` solo para él, `PUBLIC` sin escritura);
* secuencia ≥ máximo de objetos y de registro;
* siguiente id libre.

### `scripts/db/verify.sh`

* Falla (código 1) si quedan migraciones pendientes o si falta 0103 o no está operativa.
* Para `recovery` imprime **"apta para entregar al Integrante 2"** solo si todo pasa y la instancia
  está promovida; si no, imprime **"NO APTA"**.

### Recuperación y otros

* **`scripts/recovery/pitr_steps.sh promovida`.** Tras la promoción hace `ALTER SYSTEM RESET` de
  `restore_command` y `recovery_target_*`. Así un respaldo físico tomado después de esa instancia no
  hereda el objetivo, lo que provocaba `recovery ended before configured recovery target was
  reached` o `multiple recovery targets specified`.
* **`scripts/recovery/pitr_demo.sh`.** Nuevo paso **9b**: `migrate.sh recovery` y `verify.sh
  recovery` tras el PITR. El informe incluye la salida. Además, durante esta regresión se demostró
  un éxito falso del mismo tipo: el paso 5 tomaba el segmento con `… 2>/dev/null | tail -1` y, si
  el WAL no se archivaba, **simulaba igualmente la falla del nodo** (paso 6). Ver
  `evidence/08a_*`. Ahora se valida el segmento (y el instante objetivo del paso 3) y la
  demostración se detiene **antes** de matar el nodo: rc 1 con el nodo sano
  (`evidence/08c_guardia_wal/`).
* **`scripts/db/seed.sh`.** Misma corrección del `for $(nodes_expand)`: un destino inválido ya no
  devuelve 0.
* **Pruebas:**
  * `tests/container/test_recovery_migracion.sh` (nueva, 65 comprobaciones);
  * `tests/run_tests.sh` gana `[2b]` RA-01 y `[2c]` (si `pg-recovery` corre, debe estar apta);
  * `tests/container/test_ids_aislado.sh` fija `pg-recovery` a una IP inexistente dentro del
    contenedor de pruebas, para que ninguna prueba pueda alcanzar la instancia real.
* **Documentación:**
  * `Makefile` (ayuda);
  * `docs/BACKUP_RECOVERY.md` (paso 9b, procedimiento manual, después de recuperar, conflictos,
    errores);
  * `docs/INTEGRATION.md` §2.6;
  * `remediation/INTEGRATION_IMPACT.md`;
  * `remediation/GLOBAL_ID_FIX.md`;
  * guía nueva [RECOVERY_MIGRATION_GUIDE.md](RECOVERY_MIGRATION_GUIDE.md).

No se usa `SELECT EXISTS` ni el ajuste de secuencia como sustituto. La protección sigue siendo
la PK del registro de 0103, que ahora se aplica a la copia.

## 3. Archivos modificados

| Archivo | Cambio |
|---|---|
| `scripts/db/migrate.sh` | reescrito (destinos, códigos, `recovery`, inspección, respaldo previo, verificación) |
| `scripts/db/verify.sh` | pendientes, 0103 obligatoria, apta / NO APTA |
| `scripts/db/seed.sh` | propaga el destino inválido |
| `scripts/recovery/pitr_steps.sh` | `ALTER SYSTEM RESET` del objetivo tras promover |
| `scripts/recovery/pitr_demo.sh` | paso 9b + sección del informe; validación del objetivo y del WAL archivado antes de simular la falla |
| `sql/checks/verificar_0103.sql` | **nuevo** |
| `tests/run_tests.sh` | `[2b]` RA-01, `[2c]` estado de `pg-recovery` |
| `tests/container/test_recovery_migracion.sh` | **nuevo** |
| `tests/container/test_ids_aislado.sh` | aislamiento DNS de `pg-recovery` |
| `Makefile` | solo texto de ayuda |
| `docs/BACKUP_RECOVERY.md`, `docs/INTEGRATION.md` | procedimiento obligatorio |
| `remediation/INTEGRATION_IMPACT.md`, `remediation/GLOBAL_ID_FIX.md` | comando correcto |
| `remediation/RA-01/*` | **nuevos**: informe, pruebas, guía, instrucciones de auditoría, scripts de laboratorio y evidencias |

Sin cambios: `sql/migrations/**`, `docker/**`, `compose.yaml`, `scripts/lib/**`, `audit/**`
(46/46 hashes de `audit/reaudit/SHA256SUMS.json` coinciden: `evidence/09_higiene/`).

## 4. Migraciones aplicadas

| Nodo | Antes | Aplicada | Después |
|---|---|---|---|
| `pg-recovery` original (copia de `san_carlos`, campus 3, línea de tiempo 2) | 0001, 0002, 0101, 0102 | `campus/0103_registro_identificadores` (17:19:01, una transacción) | 5 migraciones, ninguna pendiente |
| Cinco campus y central | ya al día (remediación anterior) | ninguna | sin cambios |

Secuencia del procedimiento en el original (`evidence/07_original/`):

1. **Respaldo verificado previo, fuera de la herramienta.** `pg_basebackup` verificado más
   `pg_dump` en `sigtec_backups:/backups/recovery_pre_ra01/20261120T225613Z/`
   (`evidence/00_respaldo_recovery_original/`). Ese respaldo se clonó al laboratorio y se probó
   (`01_clon_lab`, `03_lab_pruebas`, `06_lab_regresion_con_clon`).
2. **Estado antes.** `make recovery-status` dio rc 2, `MIGRACIONES PENDIENTES:
   campus/0103_registro_identificadores` y NO APTA (`recovery_status_antes.log`). La huella de
   datos está en `huella_antes.txt`.
3. **`make migrate NODE=recovery`, rc 0** (`migrate_recovery.log`):
   * identidad `san_carlos`/3/`local_san_carlos` confirmada con `SIGTEC_RECOVERY_INFO`;
   * 42 objetos;
   * 16/16 disparadores;
   * secuencia 82, máximo 50;
   * registro ausente, 0 repetidos;
   * respaldo `recovery_pre_migracion/20261120T231900Z`;
   * 0103 registró 42 ids;
   * 10 PASS.
4. **Después:**
   * la huella de las ocho capas es idéntica, con los mismos conteos y md5 (`huella_diff.txt`);
   * la identidad no cambió;
   * `make recovery-status` da rc 0 y **apta** (`recovery_status_despues.log`);
   * una segunda ejecución no hace nada ni toma otro respaldo (`migrate_recovery_idempotente.log`);
   * `NODE=nodo_inexistente` da rc 2.
5. **Pruebas SQL con transacción revertida** sobre el original (`30_reglas_identificadores` +
   `40_registro_ids`): 38 PASS, 0 FAIL (`sql_tests_recovery.txt`).

## 5. Estado final de los nodos

| Nodo | Estado |
|---|---|
| `pg-recovery` original | promovida; 0103 aplicada; 42 ids registrados, 0 repetidos; 24 disparadores; próximo id `3000000083`; **apta para entregar al Integrante 2**. La reincorporación a la replicación **no está demostrada** (corresponde al Integrante 2). |
| Cinco campus y central | sin cambios de esquema; suite completa en verde (ver [RA01_TESTS.md](RA01_TESTS.md)) |
| Laboratorio `sigtec_remed` | clon del original migrado durante las pruebas; después se usó para probar la guardia del PITR (su archivo WAL de san_carlos quedó inservible por un volumen retenido, ver `evidence/08a_*`) |
| Laboratorio nuevo `sigtec_ra01` (`remediation/RA-01/lab_limpio`) | instalación desde cero: ver RA01_TESTS.md §5 |

## 6. Riesgos residuales

| Riesgo | Estado |
|---|---|
| Un superusuario o el dueño pueden deshabilitar disparadores o usar `session_replication_role = replica` | No revocable en PostgreSQL. `verificar_0103.sql` y `verificar_registro_ids.sql` lo detectan. |
| Una copia base de una instancia recuperada **antes** de esta corrección hereda `recovery_target_*` en `postgresql.auto.conf`, y `sigtec-recovery-entrypoint` no la recupera tal cual | Documentado en la guía §1 con un procedimiento sobre una copia (`clone_recovery_into_lab.sh`). Las nuevas promociones lo limpian. La imagen no se cambió. |
| `make` termina con su propio código 2 ante cualquier fallo de la receta | Imprime `Error N` con el código específico. Los códigos 1–5 son los de `scripts/db/migrate.sh` y se ven en el mensaje `RESULTADO`. |
| Objetos creados en el campus activo después del instante restaurado | Reconciliación del Integrante 2 (plantilla de secuencia, guía §5); no demostrada. |
| F-09 (falso rechazo del restore-test bajo escrituras concurrentes), F-06 (TLS no exigido), F-07 (`setup.ps1`) | Abiertos y no bloqueantes, fuera del alcance de RA-01. |
| `scripts/clean.sh` informa "Limpieza terminada" con rc 0 aunque Docker no elimine un volumen en uso por otro contenedor | Observado en el laboratorio (`evidence/08a_*`: el contenedor `sigtec_reaudit_pitr` de la auditoría retiene dos volúmenes). Ajeno a RA-01 y **no corregido**. Mitigación: la instalación limpia se repitió en un proyecto nuevo. |
| Windows/PowerShell y Linux | No ejecutados; solo macOS con Docker Desktop. |
| Paso `--alinear-clave` de `clone_recovery_into_lab.sh` | Solo para el laboratorio. Cambia la contraseña de `postgres` **en el clon** a la del laboratorio; nunca toca el original. |

## 7. Criterios de aceptación

| Criterio | Verificado | Evidencia |
|---|---|---|
| `make migrate NODE=recovery` migra una recuperada existente, accesible y promovida | sí | `07_original/migrate_recovery.log`, `05_suite`, `03_lab_pruebas` |
| Ningún éxito falso: destino desconocido, nodo omitido, conexión, SQL, autenticación, permisos, migración incompleta | sí (códigos 2/3/4/5/1; `verify` NO APTA) | RA01_TESTS §2 |
| Migración no destructiva: respaldo previo validado, inspección, conteos, duplicados, disparadores, secuencia, 0103 ya aplicada | sí; con duplicados se detiene sin cambios | §2, `07_original` |
| Verificación posterior: registro y PK, ids registrados, disparadores, seguridad de funciones, permisos de mantenimiento, unicidad en 8 capas, secuencia, datos preservados | sí (`verificar_0103.sql` 10/10, huella idéntica) | `07_original` |
| Concurrencia: conexiones independientes, carrera autorizada, id explícito sin autorización | sí | RA01_TESTS §3 |
| PITR anterior a 0103 → promoción → migración → inserción → reinicio | sí (clústeres temporales y contenedor real con el paso 9b) | `05_suite`, `08b`, `03_lab_pruebas` r13 |
| `pg-recovery` original con 0103 aplicada y apta | sí | `07_original`, `10_original_suite` |
| Regresión: 733 previas + RA-01; F-01 y F-02 siguen corregidos; respaldos lógicos y físicos; PITR; instalación limpia | sí: 799/799 en originales y en el laboratorio; instalación desde cero en `sigtec_ra01` | `06`, `08b`, `10` |
| `audit/` y `audit/reaudit/` intactos | sí (46/46 hashes) | `09_higiene` |

**Veredicto del Integrante 1: RA-01 CORREGIDO Y VERIFICADO.** No es una aprobación del proyecto
completo: esa certificación corresponde a la auditoría final.
