# F-02 — Ids explícitos sin autorización y unicidad no atómica: causa y corrección

## 1. Reproducción antes de la corrección

Laboratorio aislado `sigtec_remed`, Cartago. Evidencia:
[evidence/01_reproduccion_prefix/reproduce_audit_defects.log](evidence/01_reproduccion_prefix/reproduce_audit_defects.log).

| Caso | Resultado |
|---|---|
| F-02a: rol `remed_editor` (sin privilegio sobre la secuencia) con `SET LOCAL sigtec.permitir_id_explicito = on` inserta un id explícito | **aceptado** |
| F-02b: dos sesiones de ese rol insertan el mismo id en `puntos_interes` e `iluminacion` | ambas confirman: **1000000043 ×2** |

Los datos de los nodos originales **no** tenían duplicados (207 objetos, 207 ids distintos;
[evidence/07_original_pre_migracion/duplicados_previos.txt](evidence/07_original_pre_migracion/duplicados_previos.txt)).

## 2. Causas raíz

1. **Autorización inexistente.** `sigtec.permitir_id_explicito` es un GUC personalizado: cualquier
   rol puede asignarlo. Además `tg_asignar_identificador()` era `SECURITY DEFINER`, así que dentro
   del disparador `current_user` era el dueño y cualquier comprobación de privilegios evaluaba al
   dueño, no a quien insertaba.
2. **Unicidad no atómica.** La migración 0102 comprobaba con ocho `SELECT EXISTS` que el id no
   estuviera en otra capa. Una transacción no ve filas no confirmadas de otra; como cada capa es
   una tabla distinta, ninguna restricción impedía que dos transacciones confirmaran el mismo id.

## 3. Corrección: migración `sql/migrations/campus/0103_registro_identificadores.sql`

Migración **nueva** (0101/0102 no se editaron). Se ejecuta en una sola transacción
(`migrate.sh` usa `--single-transaction`): si algo falla no queda nada aplicado.

| Elemento | Detalle |
|---|---|
| Rol `sigtec_mantenimiento_id` | `NOLOGIN`, sin privilegios propios. Pertenecer a él es la autorización explícita del modo de mantenimiento. |
| `ops.identificadores_globales` | `id bigint PRIMARY KEY`, `campus_id`, `capa`, `origen` (`migracion_0103`/`insercion`), `registrado_en`, `sesion`; `CHECK` de campus, formato, capa y origen; `REVOKE ALL FROM PUBLIC`. |
| Carga inicial | Antes de crear nada comprueba duplicados entre capas; si los hay **aborta** (`23505`) con la lista y no modifica datos. Si el consecutivo máximo supera la secuencia, la ajusta. Registra todos los ids existentes y verifica el conteo. |
| `sigtec_id_siguiente()` | `SECURITY DEFINER`, `search_path = pg_catalog, pg_temp`. Único punto que hace `nextval`, para que la asignación pueda ser `SECURITY INVOKER` sin conceder la secuencia a los editores. |
| `sigtec_id_autorizar_explicito(bigint)` | `SECURITY DEFINER`; comprueba que el consecutivo ya fue emitido por la secuencia. `EXECUTE` **solo** para `sigtec_mantenimiento_id`. |
| `tg_asignar_identificador()` | Ahora **`SECURITY INVOKER`**. Id nulo → `sigtec_id_siguiente()`. Id explícito → exige el GUC (`23514`) **y** `pg_has_role(current_user, 'sigtec_mantenimiento_id', 'USAGE')` (`42501`) **y** la función de autorización. |
| `tg_registrar_identificador()` + `trg_30_registrar_identificador` | `AFTER INSERT` en las ocho tablas, `SECURITY DEFINER`: `INSERT … ON CONFLICT (id) DO NOTHING`; si no insertó → `23505` "el id … ya existe en el registro global del campus". |

### Por qué es seguro ante concurrencia

La unicidad la garantiza el índice de la `PRIMARY KEY` del registro, no una consulta previa.
Si dos transacciones insertan el mismo id en capas distintas, la segunda **espera** en el índice
hasta que la primera termine: si la primera confirma, la segunda recibe `23505` y se revierte
completa (fila de la capa incluida); si la primera revierte, la segunda continúa. No quedan
`SELECT EXISTS` como protección.

### Decisiones

* **Los ids eliminados no se reutilizan**: el registro conserva la entrada al borrar la fila.
  Es la opción segura para la futura replicación (un id nunca designa dos objetos distintos en el
  tiempo). `sql/checks/verificar_registro_ids.sql` informa cuántos registrados ya no existen.
* El registro está en `ops`, que no se publica.
* Las tablas de capas, sus columnas, PK, `CHECK`, índices GiST y `REPLICA IDENTITY` **no cambian**.
* Superusuarios y el dueño de las tablas pueden deshabilitar disparadores (`ALTER TABLE … DISABLE
  TRIGGER`, `session_replication_role = replica`); es una capacidad administrativa de PostgreSQL
  que no se puede retirar al superusuario. La verificación (`make verify`) detecta el resultado.

## 4. Archivos

| Archivo | Tipo |
|---|---|
| `sql/migrations/campus/0103_registro_identificadores.sql` | nuevo |
| `sql/checks/verificar_registro_ids.sql` | nuevo (objetos, repetidos entre capas, sin registro, registrados eliminados, `estado_ids`) |
| `sql/templates/ajustar_secuencia_tras_recuperacion.sql` | ajusta por encima del máximo de capas **y** del registro |
| `scripts/db/verify.sh` | ejecuta la comprobación si existe el registro; si no, lo informa |
| `scripts/backup/logical_restore_test.sh`, `physical_restore_test.sh` | comprueban el registro en la copia restaurada (24 disparadores) o informan "respaldo anterior a la migración 0103" |
| `tests/sql/40_registro_ids.sql` + `tests/container/run_sql_tests.sh` | 20 pruebas por campus (100) |
| `tests/container/test_ids_aislado.sh` | 272 pruebas en clústeres temporales |
| `docs/DATA_DICTIONARY.md`, `docs/INTEGRATION.md`, `docs/BACKUP_RECOVERY.md` | reglas, registro, conflictos |

## 5. Pruebas

### `tests/sql/40_registro_ids.sql` (transacción revertida, 20 × 5 campus)

Estructura (PK, sin acceso de `PUBLIC`, 8 disparadores, asignación `INVOKER`, funciones
`DEFINER` con `search_path` fijo, `EXECUTE` solo para mantenimiento, rol `NOLOGIN`); datos (ids
únicos entre capas, todos registrados, secuencia ≥ registro); comportamiento con roles creados
dentro de la transacción: editor inserta sin id · editor + GUC → `42501` · editor no invoca la
autorización · no escribe en el registro · no deshabilita disparadores · no activa modo réplica ·
mantenimiento con el mismo id en dos capas → `23505` · mantenimiento inserta id emitido y libre ·
no puede cambiar ids · un id existente no se reutiliza.

### `tests/container/test_ids_aislado.sh` (clústeres temporales, migraciones y carga reales)

Por cada campus: 8 sesiones simultáneas × 50 inserciones (solapamiento comprobado en
`pg_stat_activity`) sin repetidos · carrera autorizada con el mismo id (la segunda espera y
recibe `23505`; variante con reversión, en la que la segunda continúa) · prefijo y `campus_id` de
otro campus rechazados · inmutabilidad · intentos de evasión del editor · llamada directa a
`sigtec_id_siguiente()` · casos de mantenimiento · eliminación (id no reutilizable) · reinicio ·
`pg_dump`/restauración (24 disparadores; reincorporación solo tras ajustar la secuencia;
duplicado rechazado) · publicación de las 8 tablas sin `ops`, replica identity, 48 columnas.
Ruta de actualización: copia sin 0103 con un duplicado introducido → 0103 aborta sin cambios y con
los datos intactos → tras resolverlo se aplica, registro completo, idempotente.

### Resultados

| Ejecución | Resultado | Evidencia |
|---|---|---|
| Reproducción tras la corrección | F-02a rechazado (`42501`), F-02b sin duplicados, F-02c (rol autorizado): la sesión 2 esperó 3 s y recibió `23505`, 1 fila confirmada | [04](evidence/04_reproduccion_postfix/reproduce_audit_defects.log), [10](evidence/10_reproduccion_final/reproduce_audit_defects.log) |
| Migración con duplicado (laboratorio) | abortó rc=3, nada aplicado | [03](evidence/03_identificadores/lab_migracion_con_duplicado.log) |
| Migración tras resolver (laboratorio) | aplicada en 5 campus; registro = objetos | [03](evidence/03_identificadores/lab_migracion_resuelta.log) |
| `test_ids_aislado.sh` | 272 PASS, 0 FAIL | [03](evidence/03_identificadores/lab_test_ids_aislado.log), [06](evidence/06_lab_instalacion_limpia/tests/), [09](evidence/09_original_post_migracion/tests/) |
| Migración en los originales | 41 + 41 + 43 + 41 + 41 = 207 ids registrados, sin conflictos | [08](evidence/08_original_migracion/migrate.log) |
| `make verify` en los originales | `estado_ids = OK` en los cinco campus | [09](evidence/09_original_post_migracion/pipeline.log) |

## 6. Riesgos residuales

| Riesgo | Mitigación / estado |
|---|---|
| Superusuario o dueño deshabilita disparadores, o usa `session_replication_role = replica` | Capacidad administrativa no revocable; detectado por `verificar_registro_ids.sql` (`sin_registro` > 0). No replicar hacia esquemas originales. |
| `TRUNCATE` (solo dueño/superusuario) vacía una capa sin tocar el registro | Dirección segura: los ids quedan reservados y no se reutilizan. |
| Llamar directamente a `sigtec_id_siguiente()` | Solo consume un consecutivo (equivale a una inserción revertida); no registra nada. Probado. |
| Copias anteriores a 0103 (p. ej. `pg-recovery` original) | No tienen registro. **Corregido en RA-01:** `make migrate NODE=recovery` las actualiza (antes devolvía 0 sin migrar) y `make recovery-status` falla mientras falte 0103. Ver `remediation/RA-01/`. |
