# RA-01 — Pruebas ejecutadas

Todas las pruebas se ejecutaron en este equipo: macOS con Docker Desktop, PostgreSQL 17.12 y
PostGIS 3.5.4. Las evidencias están en `remediation/RA-01/evidence/`, separadas de `audit/` y de
`remediation/evidence/`. Cada resultado indicado se obtuvo ejecutando la prueba. Lo que no se
pudo verificar se dice expresamente en §8.

## 0. Resumen

| Conjunto | Dónde | Resultado | Evidencia |
|---|---|---|---|
| Reproducción ANTES (código anterior, clon del `pg-recovery` original) | laboratorio `sigtec_remed` | RA-01a y RA-01b **REPRODUCIDOS** | `02_reproduccion_antes/` |
| Reproducción DESPUÉS (código corregido, clon nuevo del original) | laboratorio | RA-01a y RA-01b **NO REPRODUCIDOS** | `04_reproduccion_despues/` |
| `test_recovery_lab.sh` (contenedor `pg-recovery` real del laboratorio, clon del original) | laboratorio | **56 PASS, 0 FAIL** | `03_lab_pruebas/test_recovery_lab.log` |
| `tests/container/test_recovery_migracion.sh` (PITR real a un instante anterior a 0103) | clústeres temporales | **65 PASS, 0 FAIL** | `05_suite/` |
| Suite completa `run_tests.sh --full`, con `pg-recovery` = clon migrado | laboratorio | **799 PASS, 0 FAIL** (733 previas + 65 + `[2c]`) | `06_lab_regresion_con_clon/` |
| `pg-recovery` original: migración, verificación, idempotencia, pruebas SQL con transacción revertida | originales | rc 0 · apta · 38 PASS, 0 FAIL | `07_original/` |
| Instalación limpia en el proyecto nuevo `sigtec_ra01` (setup → suite → respaldos → PITR con 9b → `auto.conf` limpio → suite con `[2c]` → retención) | laboratorio | todo rc 0; 798 y 799 PASS; PITR EXITOSA | `08b_lab_instalacion_limpia/` |
| Intento no limpio (volúmenes retenidos por un contenedor de la auditoría) y guardia nueva del PITR | laboratorio `sigtec_remed` | fallos explicados (§5.2); la guardia detiene la demostración sin matar el nodo | `08a_*`, `08c_guardia_wal/` |
| Suite completa y respaldos en los originales tras migrar | originales | **799 PASS, 0 FAIL**; 6 VÁLIDAS + 6 RECUPERABLES; apta | `10_original_suite/` |

## 1. Reproducción del defecto (antes y después)

Script: `remediation/RA-01/scripts/reproduce_ra01.sh <lab> <log>`. Actúa sobre el `pg-recovery` del
laboratorio, que es un clon del original creado por `clone_recovery_into_lab.sh` desde el respaldo
verificado `recovery_pre_ra01/20261120T225613Z`.

* **RA-01a.** `make migrate NODE=recovery` y, después, ¿está registrada 0103?
* **RA-01b.** Un rol `ra01_editor` (NOLOGIN, sin USAGE sobre la secuencia, INSERT en
  `puntos_interes` e `iluminacion`) activa `sigtec.permitir_id_explicito`. Dos conexiones se solapan
  e insertan el mismo id, el siguiente de la secuencia, una en cada capa.

| Caso | Antes | Después |
|---|---|---|
| RA-01a | rc **0**, 0103 **no** aplicada → REPRODUCIDO | rc 0 **y** 0103 aplicada → NO REPRODUCIDO |
| RA-01b | ambas sesiones rc 0, **2 filas** con `3000000083` → REPRODUCIDO | ambas sesiones rechazadas (psql rc 3, `42501`), **0 filas** → NO REPRODUCIDO |

## 2. Pruebas funcionales

Las comprobaciones de la suite (`05_suite`) usan el **script** y su código exacto. Las del
laboratorio (`03_lab_pruebas`) usan **`make`**, que termina con su propio código 2 ante cualquier
fallo de la receta e imprime `Error N` con el código del script.

| Caso | Comando | Esperado | Obtenido |
|---|---|---|---|
| Nodo inexistente | `migrate.sh nodo_x` / `make migrate NODE=nodo_x` | ≠ 0, sin conexiones | código **2** `destino inválido: 'nodo_x'` / make rc 2 |
| Lista con un nodo inexistente | `migrate.sh cartago,nodo_x` | ≠ 0, nada aplicado | **2** |
| `seed` con destino inválido | `seed.sh recovery` | ≠ 0 | rc 1 (el código anterior tenía el mismo patrón `for … $(nodes_expand)`; su rc 0 previo no se midió) |
| Servidor inaccesible | `pg-recovery` → `127.0.0.9`, `SIGTEC_WAIT_TIMEOUT=3` | ≠ 0 | **3** `no aceptó conexiones en 3s` |
| Contenedor detenido | `docker stop` del `pg-recovery` de laboratorio | ≠ 0, sin cambios | make rc 2 (script 3); sin cambios |
| Credenciales incorrectas | contraseña errónea | ≠ 0, sin secreto en la salida | **3** `password authentication failed`; la contraseña no aparece |
| No promovida | standby en recuperación | ≠ 0 | **4** `sigue en recuperación` |
| Identidad inconsistente | `SIGTEC_RECOVERY_INFO` = `limon` frente a `ops.node_info` = `san_carlos` | ≠ 0 | **4** |
| Ids repetidos | dos capas con el mismo id | ≠ 0; ni 0103, ni respaldo, ni cambios | **5** `3000000075 en iluminacion+puntos_interes`; huella idéntica |
| Error SQL en una migración | `0199` con `1/0` en una copia de `SIGTEC_HOME` | ≠ 0, sin estado parcial | **1** `division by zero`; ni registrada ni objetos; `verify` NO APTA |
| Error de permisos | `0199` con `SET ROLE` a un rol sin privilegios | ≠ 0, sin estado parcial | **1** `permission denied`; ni registrada ni objetos; `verify` NO APTA |
| Migración incompleta / pendiente | `verify.sh recovery` con 0103 o `0199` pendiente | ≠ 0 | rc **1**, `MIGRACIONES PENDIENTES … NO APTA` |
| Aplicación sobre un recuperado sin migrar | `migrate.sh recovery` | 0; 0103 aplicada | **0**; 10 PASS |
| Idempotencia | segunda ejecución | 0; nada reaplicado; sin nuevo respaldo | **0**; `ninguna pendiente`; respaldos = 1 |

## 3. Pruebas de integridad de identificadores

Se ejecutaron después de migrar, en la recuperación de la suite y en el clon del laboratorio.

| Caso | Resultado |
|---|---|
| Ids existentes | registrados todos (`objetos_registrados`); los datos y la huella md5 de las 8 capas no cambian |
| Duplicado en dos capas antes de migrar | código 5, sin modificar nada (§2) |
| Editor + GUC con id explícito | `42501` |
| Editor llama a `sigtec_id_autorizar_explicito` / escribe en el registro / `DISABLE TRIGGER` / `session_replication_role` | `42501` en todos |
| Rol de mantenimiento con el mismo id en dos capas | `23505` |
| Carrera autorizada con el mismo id (dos conexiones solapadas) | la primera confirma; la segunda **espera 3 s** y recibe `23505`; **1 fila** |
| 8 conexiones independientes × 25 inserciones automáticas | solapamiento comprobado en `pg_stat_activity` (`PGAPPNAME`, `xact_start`): 8 transacciones abiertas a la vez; 200 filas, 200 registradas, 0 repetidos, 0 sin registro |
| Siguiente id | `secuencia_cubre_ids` y `siguiente_id_libre` PASS; tras las inserciones, el siguiente automático es libre y queda registrado |
| Ningún duplicado confirmado | `ids_unicos_entre_capas` = 0 en cada verificación |

En el original (sin dejar filas): `tests/sql/30_reglas_identificadores.sql` + `40_registro_ids.sql`
dentro de una transacción revertida dieron **38 PASS, 0 FAIL**. Incluyen editor + GUC → `42501` y
mantenimiento con el mismo id en dos capas → `23505`. Consumen algunos consecutivos de la
secuencia, que no es transaccional.

## 4. Pruebas de recuperación

`tests/container/test_recovery_migracion.sh`, fases 1–2, PITR real en clústeres temporales:

1. Origen con 0101/0102 (copia del código sin 0103) y datos.
2. `pg_basebackup`.
3. Cambio A, luego **objetivo** `recovery_target_time`.
4. Se aplica 0103 en el origen con el `migrate.sh` real, después cambio B.
5. Se archiva el WAL (`archive_command` atómico, espera en `pg_stat_archiver`).
6. PITR al objetivo, con promoción e identidad (`SIGTEC_RECOVERY_INFO`).

Comprobado:

* promovida;
* A presente y B ausente;
* esquema **anterior a 0103** (instante previo a la migración);
* F-02 reproducido en la copia sin migrar (2 filas);
* migración → 0103 aplicada, ids y secuencia correctos;
* inserción;
* **reinicio** (`pg_ctl restart`): datos, 0103, `verify` apta e inserción tras reiniciar.

El caso de un instante anterior a 0103 queda así detectado (`verify` NO APTA, `[2c]`) y corregido
(`migrate.sh recovery`) de forma reproducible en cada `make test`.

Con el contenedor real: `test_recovery_lab.sh` r13 (`docker restart` del `pg-recovery` de
laboratorio) da datos, 0103, `verify` e inserción PASS.

PITR completo con el contenedor real (`pitr_demo.sh`, paso 9b): ver §5.

## 5. Regresión e instalación limpia (laboratorio)

### 5.1 Suite completa con el clon migrado del original (`06_lab_regresion_con_clon/`)

`run_tests.sh --full` en `sigtec_remed`, con `pg-recovery` = clon del original migrado:

* `RESUMEN: 392 PASS` (SQL/PostGIS);
* `respaldos: 36 PASS` (regresión F-01);
* `identificadores: 272 PASS` (regresión F-02);
* `recuperación RA-01: 65 PASS`;
* `[2c] recovery.migraciones_y_registro` PASS;
* higiene, idempotencia y persistencia PASS.

Total **799 PASS, 0 FAIL**, rc 0.

### 5.2 Intento de reinstalación de `sigtec_remed` no limpio (`08a_*`, conservado)

`clean.sh --yes` no pudo borrar dos volúmenes. Los retiene el contenedor detenido
`sigtec_reaudit_pitr` de la auditoría, que no se tocó, y aun así `clean.sh` informó éxito. El WAL
de san_carlos conservaba segmentos antiguos, lo que dio FAIL en el archivado, en la restauración
física de san_carlos y en el PITR. Ese intento destapó un éxito falso en `pitr_demo.sh`, ya
corregido: el paso 5 simulaba la falla del nodo sin WAL archivado. Guardia comprobada en
`08c_guardia_wal/`: con el archivo roto, la demostración termina con rc **1** en el paso 5 y el nodo
sigue sano.

### 5.3 Instalación desde cero en un proyecto nuevo `sigtec_ra01` (`08b_lab_instalacion_limpia/`)

Comando: `lab_instalacion_limpia.sh <ev> "" sigtec_ra01`. Usa el código actual, una plantilla con
puertos 57440–57446 y la imagen `sigtec-ra01/…`, y **sin `.env`**: `setup.sh` generó los secretos.

| Paso | rc | Resultado |
|---|---|---|
| `clean.sh --yes` | 1 | esperado: no hay `.env` ni recursos; `clean.sh` se niega ("Ejecute primero: scripts/setup.sh") |
| `setup.sh` (sin puertos exportados) | 0 | seis nodos sanos, migraciones y datos |
| `run_tests.sh --full` | 0 | 392 + 36 + 272 + 65 PASS, 0 FAIL (`pg-recovery` aún no existe, `[2c]` informativo) |
| `make backup` | 0 | lógico + físico de los seis |
| `make restore-test` | 0 | 6 restauraciones lógicas VÁLIDAS + 6 copias físicas RECUPERABLES |
| `pitr_demo.sh san_carlos --reset` | 0 | **PITR EXITOSA**: A presente, B ausente, promovida; **paso 9b** `migrate.sh recovery` + `verify` apta |
| `make recovery-status` | 0 | apta para entregar |
| `postgresql.auto.conf` sin objetivo | 0 | solo la cabecera; tras `docker restart`, 0 parámetros `recovery_target*` y `restore_command`, `recovery-status` rc 0 (`autoconf_tras_reinicio.txt`) |
| `run_tests.sh --full` con `pg-recovery` | 0 | 799 PASS, 0 FAIL, incluido `[2c]` |
| `make wal-retention` (simulación) | 0 | nada eliminado |

Los valores de `recovery_target_*` que `pg_settings` mostraba antes del reinicio eran los cargados en
memoria. Son parámetros de arranque: `pg_reload_conf()` no los cambia, y el archivo ya estaba
limpio.

## 6. Originales tras la migración

### 6.1 `pg-recovery` original (`07_original/`)

| Comprobación | Resultado |
|---|---|
| Antes: `make recovery-status` | rc ≠ 0; `MIGRACIONES PENDIENTES: campus/0103_registro_identificadores`; `FALTA el registro global`; NO APTA |
| `make migrate NODE=recovery` | rc 0; inspección sin repetidos; respaldo `recovery_pre_migracion/20261120T231900Z`; 42 ids registrados; 10 PASS |
| Huella de las 8 capas antes y después | idéntica (8 filas, mismos conteos y md5) |
| Identidad (`ops.node_info`) | `san_carlos` / 3 / `local_san_carlos`, sin cambios |
| `make recovery-status` | rc 0, apta |
| Segunda ejecución | rc 0, nada aplicado, sin respaldo nuevo |
| `make migrate NODE=nodo_inexistente` | rc 2 (`destino inválido`) |
| `30_reglas_identificadores` + `40_registro_ids` (transacción revertida) | 38 PASS, 0 FAIL |

### 6.2 Suite completa, respaldos y restauración (`10_original_suite/`)

| Paso | rc | Resultado |
|---|---|---|
| `tests/run_tests.sh --full` | 0 | **799 PASS, 0 FAIL**. 392 SQL/PostGIS, 36 respaldos (F-01), 272 identificadores (F-02), 65 RA-01, `[2c] recovery.migraciones_y_registro` PASS, higiene (`repo.sin_rutas_absolutas` incluida), idempotencia, persistencia |
| `make backup` | 0 | lógico + físico de los seis nodos en servicio |
| `make restore-test` | 0 | 6 VÁLIDAS + 6 RECUPERABLES |
| `make recovery-status` | 0 | apta |

Después de la suite siguen presentes los 15 volúmenes del proyecto `sigtec`. Un primer intento de
esta corrida se detuvo a los pocos segundos porque la ruta de evidencias era absoluta y habría
fallado la comprobación de rutas. Se dejó terminar el contenedor de pruebas que estaba en curso y
se repitió completa. Sus registros parciales no se conservan en el proyecto.

En los originales **no** se ejecutó `pitr_demo.sh --reset`, porque eliminaría el volumen de
`pg-recovery`. El PITR con el contenedor real y el paso 9b se demostró en `sigtec_ra01` (§5.3).

## 7. Comandos

```bash
# Reproducción en el laboratorio (clon del original desde el respaldo verificado)
bash remediation/RA-01/scripts/clone_recovery_into_lab.sh remediation/lab 20261120T225613Z --alinear-clave
bash remediation/RA-01/scripts/reproduce_ra01.sh remediation/lab /tmp/ra01.log
# Contenedor real del laboratorio (clon nuevo sin alinear la clave)
bash remediation/RA-01/scripts/test_recovery_lab.sh remediation/lab /tmp/ra01_lab.log
# Suite RA-01 sola y suite completa
cd remediation/lab && docker compose --profile tools run --rm -T sigtec-tools tests/container/test_recovery_migracion.sh
cd remediation/lab && bash tests/run_tests.sh --full
# Instalación limpia en un laboratorio nuevo (sigtec_ra01, puertos 57440–57446)
bash remediation/RA-01/scripts/lab_instalacion_limpia.sh /tmp/ra01_limpia "" sigtec_ra01
# Originales
make recovery-status
make migrate NODE=recovery
make test
```

## 8. No verificado

* Windows/PowerShell y Linux: no ejecutados.
* La reincorporación de `pg-recovery` a la replicación (Integrante 2): fuera de alcance y **no
  demostrada**.
* Que una copia base antigua con `recovery_target_*` heredado se recupere con
  `sigtec-recovery-entrypoint` **sin** sanear la copia: no ocurre. Se documenta el procedimiento
  sobre una copia, y la imagen no se cambió.
