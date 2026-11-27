# Respaldo y recuperación SIG-TEC

Todo se ejecuta con las herramientas nativas de PostgreSQL 17.12 incluidas en la imagen del
proyecto (contenedor `sigtec-tools`); no hace falta PostgreSQL en el host. Cada operación deja
un registro en `evidence/backups/` o `evidence/pitr/` y una línea en `/backups/backup_log.tsv`.

## 1. Dónde queda cada cosa

| Elemento | Ubicación (volumen Docker) | Ruta dentro de los contenedores |
|---|---|---|
| Respaldos lógicos | `sigtec_backups` | `/backups/logical/<nodo>/<AAAAMMDDTHHMMSSZ>/` |
| Respaldos físicos | `sigtec_backups` | `/backups/physical/<nodo>/<AAAAMMDDTHHMMSSZ>/` |
| Bitácora de respaldos | `sigtec_backups` | `/backups/backup_log.tsv` |
| WAL archivado de cada nodo | `sigtec_walarchive_<nodo>` | `/var/lib/postgresql/wal_archive` en el nodo · `/archives/<nodo>` (solo lectura) en `sigtec-tools` y `pg-recovery` |
| Instancia recuperada | `sigtec_pgdata_recovery` | servicio `pg-recovery`, `127.0.0.1:55436` |

Contenido de un respaldo lógico: `sigtec.dump` (`pg_dump -Fc -Z 6`), `globals.sql`
(`pg_dumpall --globals-only --no-role-passwords`), `toc.txt` (`pg_restore --list`) y
`manifest.txt` (versiones, tamaño, SHA-256, conteo por capa, último valor de la secuencia).

Contenido de un respaldo físico: `data/` (`pg_basebackup -Fp -X stream -c fast
--manifest-checksums=SHA256`, con `backup_label` y `backup_manifest`) e `info.txt` (LSN y
segmento WAL de inicio, resultado de `pg_verifybackup`).

### Comportamiento ante fallos (corrección F-01)

* Cada nodo se respalda en `<nodo>/.en-curso-<UTC>-<pid>/`. Solo después de **validar** la copia
  se publica con un `rename` atómico a `<nodo>/<UTC>/` y se registra `OK` en la bitácora.
* Validación lógica: `pg_restore --list` (TOC), lectura completa de todos los bloques de datos
  (`pg_restore -f /dev/null`, detecta truncamiento), presencia de PostGIS, `ops.node_info` y los
  datos de las ocho capas, y `globals.sql` con roles.
* Validación física: `PG_VERSION` 17, `backup_label`, `backup_manifest`, `pg_control` y
  `pg_verifybackup` (sumas SHA-256 y WAL).
* Si cualquier etapa falla (autenticación, conexión, escritura, validación) el nodo se marca
  `ERROR` en la bitácora, el directorio de trabajo pasa a `.fallido-<UTC>-<pid>/` **sin la carga
  útil** (solo diagnóstico), el último respaldo publicado no cambia y el script termina con código
  ≠ 0; `make backup` se detiene y no ejecuta la etapa siguiente.
* `latest_dir`, las pruebas de restauración, el PITR y la retención solo ven respaldos publicados
  (los nombres con punto no se listan).
* Diagnóstico: el mensaje de PostgreSQL/libpq se muestra sangrado (`| …`); nunca la contraseña.
* La restauración completa no se ejecuta en cada respaldo: es la prueba periódica
  `make restore-test`.

Pruebas: `tests/container/test_backup_failures.sh` (36 casos; contraseña incorrecta en los seis
nodos, usuario inexistente, servidor inaccesible, sin permiso de escritura, directorio inválido,
escritura interrumpida, código a través de un pipeline, respaldo y restauración válidos, respaldo
anterior conservado, fallo parcial, archivos dañados). Forma parte de `make test`.

Los respaldos se toman con el rol **`sigtec_backup`** (`LOGIN REPLICATION`, miembro de
`pg_read_all_data`, sin superusuario); su contraseña se genera en `.env`.

Copiar respaldos al host (por ejemplo para guardarlos fuera de Docker; `backups_export/` está en
`.gitignore`):

```bash
docker compose --profile tools run --rm -v "$PWD/backups_export:/export" sigtec-tools \
  -c 'cp -a /backups/logical /backups/physical /export/'
```

## 2. Respaldo lógico (pg_dump)

```bash
make backup-logical NODE=all          # o NODE=san_carlos, NODE=campus ...
scripts/backup/run.sh logical_backup.sh cartago limon
```

Por nodo: `pg_dump` como `sigtec_backup`, globales sin contraseñas, lectura del TOC para
comprobar que el archivo es legible, SHA-256 y conteos. Resultado real (20 nov 2026):
seis nodos OK; central ≈ 8,6 KB, cada campus ≈ 75 KB y 140 entradas en el TOC.

### Probar la restauración lógica (aislada)

```bash
make restore-logical-test NODE=all
```

Por nodo: crea un clúster **temporal** dentro de `sigtec-tools` (puerto interno 5546, se
destruye al final), comprueba el SHA-256 del manifiesto, restaura con
`pg_restore --exit-on-error --no-subscriptions` y verifica: PostGIS, `ops.node_info`, conteos
por capa iguales al manifiesto, validación geométrica de las ocho capas, valor de la
secuencia y los 16 disparadores de identificadores. Ninguna base en servicio se toca.
Resultado real: seis nodos **VÁLIDO**.

### Restauración lógica real

Solo cuando se quiera reemplazar el contenido de un nodo (operación destructiva para ese nodo):

```bash
# 1) Elegir el respaldo
make backup-list
# 2) Restaurar en una base nueva del mismo nodo y revisar antes de cambiar nada
docker compose --profile tools run --rm -T sigtec-tools -c '
  . scripts/lib/db.sh
  D=/backups/logical/san_carlos/<FECHA>/sigtec.dump
  psql_su san_carlos -c "CREATE DATABASE sigtec_restaurada"
  PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -h pg-san-carlos -U postgres \
      -d sigtec_restaurada --exit-on-error --no-subscriptions "$D"'
```

`--no-subscriptions` evita que, cuando exista la replicación del Integrante 2, una restauración
active suscripciones contra el publicador original. Las publicaciones sí se restauran; las
ranuras de replicación no forman parte de un `pg_dump`.

## 3. Respaldo físico (pg_basebackup)

```bash
make backup-physical NODE=all
```

Por nodo: `pg_basebackup` por el protocolo de replicación (regla `host replication
sigtec_backup … scram-sha-256` en `pg_hba.conf`), WAL incluido por *streaming*, checkpoint
rápido, manifiesto con SHA-256 y verificación inmediata con `pg_verifybackup`.
Resultado real: seis nodos, `backup successfully verified`, ≈ 54 MiB cada uno.

### Probar la recuperación física (aislada)

```bash
make restore-physical-test NODE=all
```

Copia el respaldo a un clúster temporal (puerto interno 5547), configura
`restore_command` contra el archivo WAL del nodo y `recovery_target = 'immediate'`, arranca
con `ssl=off archive_mode=off` (para no escribir en el archivo del nodo), espera la promoción y
verifica PostGIS, nodo, conteos y validación. Resultado real: seis nodos **RECUPERABLE**
(línea de tiempo 2).

`make restore-test` ejecuta ambas pruebas (lógica y física).

## 4. Archivado WAL y retención

Configuración (`docker/postgis/conf/postgresql.conf`): `archive_mode = on`,
`archive_timeout = 300` s y `archive_command = '/usr/local/bin/sigtec-archive-wal "%p" "%f"'`.
El script copia a un temporal, hace `sync` y renombra (copia atómica y durable); si el
segmento ya existe y es idéntico devuelve éxito, y si existe con contenido distinto falla
(no sobrescribe). Estado del archivado:

```bash
make verify NODE=all      # columnas wal_archivados / archivado_fallido
make backup-list          # respaldos y segmentos archivados por nodo
```

```sql
SELECT archived_count, failed_count, last_archived_wal, last_failed_wal FROM pg_stat_archiver;
```

Retención: se conservan los **N** respaldos físicos más recientes por nodo y el WAL necesario
para recuperar desde el más antiguo de ellos (ventana PITR = desde ese respaldo hasta el último
WAL archivado).

```bash
make wal-retention NODE=all KEEP=2            # simulación (pg_archivecleanup -n), no borra
make wal-retention NODE=san_carlos KEEP=2 APPLY=1   # borra respaldos sobrantes y WAL anterior
```

La depuración se ejecuta dentro del contenedor del nodo, dueño del archivo. Resultado real de
la simulación en San Carlos con `KEEP=1`: 4 segmentos eliminables.

## 5. Recuperación a un instante (PITR)

### Demostración automatizada

```bash
make pitr-demo                 # NODE=san_carlos por omisión
scripts/recovery/pitr_demo.sh san_carlos --reset     # si ya existe una recuperación previa
```

| Paso | Acción |
|---|---|
| 0 | Precondiciones: nodo sano, sin instancia de recuperación previa (o `--reset`) |
| 1 | Respaldo físico base nuevo + `pg_verifybackup` |
| 2 | **Cambio A**: inserta un punto de interés `PITR-A <corrida>` y su marca en `ops.recovery_markers` |
| 3 | **Instante objetivo**: `clock_timestamp()` entre A y B (con LSN) |
| 4 | **Cambio B**: modifica A e inserta `PITR-B <corrida>` |
| 5 | `pg_switch_wal()` y espera a que el segmento con A, objetivo y B esté archivado. **Si no se archiva, la demostración termina con error antes del paso 6** (el nodo no se detiene) |
| 6 | **Falla simulada**: `docker compose kill -s SIGKILL pg-san-carlos` (los volúmenes quedan intactos) |
| 7 | Levanta `pg-recovery` con el respaldo del paso 1, el WAL de San Carlos (solo lectura) y `recovery_target_time` = objetivo; espera la promoción |
| 8–9 | Verifica: A presente con su valor previo, B ausente (inserción y actualización), instancia promovida, nueva línea de tiempo |
| 9b | `migrate.sh recovery` (= `make migrate NODE=recovery`): aplica las migraciones posteriores al instante restaurado y comprueba 0103; luego `verify.sh recovery` (capas, migraciones pendientes, registro de ids). Tras la promoción se retiran de `postgresql.auto.conf` los parámetros del PITR |
| 10 | Vuelve a iniciar el nodo original y comprueba que conserva su estado completo (no se sobrescribió) |

Informe: `evidence/pitr/pitr_<corrida>.md` (más el `.log`). Corrida real `20261120T172854Z`
(instalación limpia): **EXITOSA** — commit A 17:28:57.800 UTC < objetivo 17:29:00.366 UTC <
commit B 17:29:02.880 UTC; PostgreSQL registró `recovery stopping before commit of transaction
793` (la primera transacción confirmada después del objetivo) y `selected new timeline ID: 2`.

### Procedimiento manual

```bash
# 1. Respaldo físico de partida (o uno existente: make backup-list)
make backup-physical NODE=san_carlos
# 2. Elegir el objetivo; debe ser POSTERIOR al fin del respaldo y anterior al error
# 3. Levantar la instancia aislada
RECOVERY_SOURCE_NODE=san_carlos \
RECOVERY_BASEBACKUP=/backups/physical/san_carlos/<FECHA>/data \
RECOVERY_TARGET_TIME='2026-11-20 17:29:00+00' \
docker compose --profile recovery up -d pg-recovery
# 4. Revisar el registro
docker compose --profile recovery logs pg-recovery | grep -E 'recovery|timeline'
# 5. OBLIGATORIO: migraciones posteriores al instante restaurado (ver "Después de recuperar")
make migrate NODE=recovery
# 6. Verificar: debe terminar con "apta para entregar" y código 0
make recovery-status
make psql NODE=recovery
```

Guía completa (PITR → promoción → migración → validación → entrega al Integrante 2):
[remediation/RA-01/RECOVERY_MIGRATION_GUIDE.md](../remediation/RA-01/RECOVERY_MIGRATION_GUIDE.md).

En vez de `RECOVERY_TARGET_TIME` se puede usar `RECOVERY_TARGET_NAME` (un punto creado con
`SELECT pg_create_restore_point('antes_de_migrar')`) o `RECOVERY_TARGET_LSN`;
`RECOVERY_TARGET_INCLUSIVE=off` detiene la recuperación justo antes del objetivo. Sin objetivo,
se reproduce todo el WAL disponible. `sigtec-recovery-entrypoint` solo prepara la recuperación
si el volumen está vacío: para otro intento, `make recovery-clean` (pide escribir `ELIMINAR`) y
volver al paso 3. Los parámetros aplicados quedan en `$PGDATA/SIGTEC_RECOVERY_INFO`.

### Después de recuperar

* La instancia recuperada es independiente: el nodo original **no** se modifica.
* **Migraciones posteriores al instante restaurado (obligatorio).** Recuperar un instante o un
  respaldo anterior a una migración restaura también el esquema anterior. Un nodo recuperado
  anterior a `0103` **admite ids repetidos entre capas** (hallazgo RA-01). `make migrate` sin
  `NODE` recorre solo los seis nodos en servicio (avisa si `pg-recovery` está atrasada); la
  instancia recuperada se actualiza con:

  ```bash
  make migrate NODE=recovery
  make recovery-status          # "apta para entregar" y código 0
  ```

  El comando exige que `pg-recovery` exista, responda y esté **promovida**; toma la identidad
  (campus, esquema) de la propia copia (`ops.node_info`, contrastada con
  `SIGTEC_RECOVERY_INFO`) sin reescribirla; inspecciona migraciones, conteos, ids repetidos,
  disparadores y secuencia; si hay ids repetidos **se detiene sin cambiar nada**; antes de
  aplicar toma y valida un `pg_dump` en `/backups/recovery_pre_migracion/<UTC>/`; y al terminar
  exige que no queden migraciones pendientes y que `sql/checks/verificar_0103.sql` pase completo
  (registro, PK, 24 disparadores, modos de seguridad, permisos, secuencia, siguiente id).
  Códigos: 0 correcto · 1 error SQL/migración/verificación · 2 destino inválido ·
  3 inexistente, inaccesible o credenciales rechazadas · 4 no promovida o identidad
  inconsistente · 5 ids repetidos. Repetirlo es seguro (no reaplica nada).
* **Respaldo de una instancia ya recuperada.** Su `postgresql.auto.conf` conservaba el objetivo
  del PITR; una copia física tomada de ella lo hereda y una recuperación posterior desde esa
  copia falla (`recovery ended before configured recovery target was reached` o `multiple
  recovery targets specified`). `pitr_demo.sh` ahora retira esos parámetros al promover
  (`ALTER SYSTEM RESET`). Para una copia antigua que aún los tenga, quite las líneas
  `recovery_target*` / `restore_command` del `postgresql.auto.conf` **de una copia** del respaldo
  y recupere con un objetivo explícito (p. ej. `RECOVERY_TARGET_LSN` = `End-LSN` de su
  `backup_manifest`); ver la guía RA-01.
* **Secuencia de identificadores**: la recuperada vuelve al valor registrado en el WAL (que va
  32 valores por delante, por eso suele quedar por encima de lo emitido). Antes de usarla para
  escribir, si el central ya tiene ids más altos de ese campus, ajústela (nunca retrocede):

  ```bash
  docker compose --profile tools run --rm -T sigtec-tools -c '. scripts/lib/db.sh
    psql_su recovery -v schema=local_san_carlos -v campus_id=3 -v max_id=3000000100 \
      -f sql/templates/ajustar_secuencia_tras_recuperacion.sql'
  ```

  Probado en `pg-recovery`: 82 → 100; con un `max_id` menor no cambia; el siguiente `INSERT`
  recibió `3000000101`. Ejecútela **después** de `make migrate NODE=recovery`: la plantilla
  consulta el registro de identificadores, que no existe en una copia anterior a 0103.
* **Registro de identificadores**: `ops.identificadores_globales` se recupera junto con los
  datos (mismo instante). Los objetos creados después del objetivo no están en el registro
  recuperado; para reincorporar uno con su id original: (1) ajuste la secuencia con la plantilla
  anterior, (2) inserte como miembro de `sigtec_mantenimiento_id` con
  `SET sigtec.permitir_id_explicito = on`. Un id ya presente en el registro (incluso de un objeto
  eliminado) se rechaza con `23505`. Verificación: `make recovery-status` incluye
  `sql/checks/verificar_registro_ids.sql`.

### Reincorporación a la replicación

Cuando `make recovery-status` indique que `pg-recovery` está apto, pausa las ediciones y detén el nodo original. El siguiente ejemplo reincorpora San Carlos.

```bash
docker compose stop pg-san-carlos
python3 scripts/distributed/manage.py rejoin --node san_carlos
python3 scripts/distributed/manage.py verify
python3 scripts/integrante3/manage.py setup
```

Usa `python` si así se llama tu intérprete. Las copias de ese campus se sincronizan con el estado restaurado. Los cambios posteriores al instante elegido salen de las vistas distribuidas. Mantén detenido el nodo original e instala de nuevo el ZIP que genera el último comando para conectar QGIS al nodo recuperado.

## 6. Conflictos de identificadores

La migración `0103_registro_identificadores` comprueba, antes de crear el registro, que ningún id
aparezca en dos capas del mismo campus. Si encuentra conflictos **aborta sin modificar nada**
(transacción única) y los informa, por ejemplo:

```
ERROR:  SIG-TEC 0103: 1 identificador(es) repetido(s) entre capas de local_cartago: 1000000043 en iluminacion+puntos_interes
```

No borra ni renumera datos automáticamente. Procedimiento (decisión del administrador):

1. Respalde el nodo (`make backup NODE=cartago`).
2. Revise ambos objetos (`SELECT * FROM local_cartago.<capa> WHERE id = …`) y decida cuál conserva el id.
3. Para el otro: inserte una copia **sin** id (recibe uno nuevo) y elimine la fila original.
   Como superusuario, dentro de una transacción.
4. Repita `make migrate NODE=cartago` y `make verify NODE=cartago`.

En una instancia recuperada el procedimiento es el mismo sobre `pg-recovery`:
`make migrate NODE=recovery` detecta los ids repetidos **antes** de tocar nada y termina con
código 5 listándolos (`ids repetidos entre capas: 3000000083 en iluminacion+puntos_interes`);
resuélvalos con `make psql NODE=recovery` y repita el comando.

Con 0103 aplicada, el registro impide nuevos conflictos. Solo un superusuario (dueño de las
tablas) puede eludirlo deshabilitando disparadores (`ALTER TABLE … DISABLE TRIGGER`,
`session_replication_role = replica`); esas son capacidades administrativas excepcionales, no
rutas autorizadas, y `make verify` / `sql/checks/verificar_registro_ids.sql` detectan el resultado.

## 7. Interpretación de errores frecuentes

| Mensaje | Causa probable | Acción |
|---|---|---|
| `pg_dump: error: connection … password authentication failed for user "sigtec_backup"` | Rol sin crear o contraseña distinta a `.env` | `make migrate` (reaplica `sql/roles/sigtec_backup.sql` con la contraseña de `.env`) |
| `pg_basebackup: … no pg_hba.conf entry for replication connection` | Conexión de replicación con otro usuario | Usar `sigtec_backup`; solo ese rol puede replicar |
| `pg_verifybackup: error: checksum mismatch for file …` | Respaldo dañado o modificado | Descartar y tomar uno nuevo |
| `pg_restore: error: could not execute query: ERROR: type "geometry" does not exist` | Destino sin PostGIS | La prueba usa clústeres con PostGIS 3.5.4; en otro destino, `CREATE EXTENSION postgis` antes |
| `archive command failed with exit code 1` / `failed_count > 0` | Volumen de archivo lleno, sin permisos o segmento distinto ya archivado | `docker compose logs pg-<nodo>`; revisar espacio; nunca borrar segmentos a mano: `make wal-retention` |
| `could not open file "…/0000000100000000000000XX": No such file` en `restore_command` | Ese segmento no fue archivado (o el objetivo está fuera de la ventana) | Normal al final del WAL; si ocurre antes del objetivo, el WAL está incompleto: usar un respaldo más reciente |
| `FATAL: recovery ended before configured recovery target was reached` | Objetivo posterior al último WAL archivado | Elegir un objetivo anterior o esperar al archivado (`pg_switch_wal()`) |
| `FATAL: requested recovery stop point is before consistent recovery point` | Objetivo anterior al fin del respaldo base | Usar un respaldo más antiguo |
| `pg_dump: … password authentication failed` y `ERROR respaldando <nodo>: no se publicó ningún respaldo` | Contraseña de `sigtec_backup` distinta entre `.env` y el nodo | `make migrate NODE=<nodo>` y repetir; no hay respaldo nuevo publicado |
| `pg_restore no pudo leer todos los bloques de datos` | El archivo se truncó o dañó durante la escritura | El respaldo no se publicó; revisar espacio en disco y repetir |
| `SIG-TEC: el rol … no está autorizado para insertar identificadores explícitos` (42501) | `sigtec.permitir_id_explicito` sin pertenecer a `sigtec_mantenimiento_id` | Omitir `id`, o `GRANT sigtec_mantenimiento_id TO <operador>` si es una reincorporación legítima |
| `SIG-TEC: el id … ya existe en el registro global del campus` (23505) | El id ya fue asignado en alguna capa (o pertenecía a un objeto eliminado) | Omitir `id` para recibir uno nuevo |
| `ERROR: destino inválido: 'X'` (código 2) | `NODE` mal escrito | `NODE=all`, `campus`, `recovery` o un nodo del catálogo |
| `ERROR: pg-recovery no existe o no está en ejecución` (código 3) | No hay instancia recuperada o está detenida | `make recovery-status`; créela con un PITR |
| `ERROR: pg-recovery sigue en recuperación` (código 4) | Aún reproduce WAL o está en pausa | Esperar la promoción (o `SELECT pg_promote()`) y repetir |
| `MIGRACIONES PENDIENTES … NO APTA` en `make recovery-status` | Copia anterior a una migración | `make migrate NODE=recovery` |
| `sigtec-recovery: no es un respaldo físico válido` | `RECOVERY_BASEBACKUP` no apunta al directorio `data` del respaldo | Usar `/backups/physical/<nodo>/<FECHA>/data` |
| `pg-recovery` arranca pero no aplica un nuevo objetivo | El volumen ya tenía una recuperación previa | `make recovery-clean` y repetir |
