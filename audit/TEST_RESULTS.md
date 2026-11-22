# Pruebas y resultados

Auditoría: 20 de noviembre de 2026. Zona de presentación: America/Costa_Rica (UTC−06). Los nombres y objetivos PITR que terminan en Z usan UTC. No se cuentan lecturas de archivos como pruebas funcionales.

## Modalidades

- **EJECUTADA:** comando realizado durante esta auditoría, con evidencia en `raw/` o `lab/evidence/`.
- **EVIDENCIA EXISTENTE:** artefacto anterior inspeccionado, sin atribuir su ejecución a esta auditoría.
- **ESTÁTICA:** conclusión derivada del código o configuración; no demuestra ejecución en otra plataforma.
- **NO EJECUTADA:** capacidad que no se probó; no se marca aprobada por inferencia.

Los comandos se ejecutaron desde la raíz indicada por el usuario, salvo las órdenes de instalación/prueba que se ejecutaron en `audit/lab/`. Se inspeccionaron primero los scripts de instalación, pruebas, respaldo, recuperación y limpieza. No se ejecutó `clean.sh`, no se utilizó `down -v`/`down --volumes`, no se restauró encima de ninguna base original y no se aplicó retención destructiva.

## Registro de pruebas

| ID | Modalidad | Comando o instrumento | Resultado y evidencia |
|---|---|---|---|
| T-01 | EJECUTADA | `pypdf.PdfReader` del Python incluido en el runtime; render con `pypdfium2` | Leídos los 16 folios del enunciado y los 6 de distribución. Tablas de capas/respaldos/contrato contrastadas visualmente. `reference/*.txt`, `reference/*.png`. |
| T-02 | EJECUTADA / ESTÁTICA | `pwd`, `rg --files`, `ls -la`, `git status --short`, búsqueda de AGENTS | Raíz correcta; no hay repositorio Git en esta carpeta; `git status` terminó 128. No se encontraron instrucciones AGENTS aplicables. Inventario SHA-256 de 69 archivos originales en `raw/original_hashes.json`. |
| T-03 | EJECUTADA | `bash -n` sobre scripts shell, entrypoints y pruebas | 26 archivos, 0 errores sintácticos; `raw/shell_syntax.txt`. Esto no verifica PowerShell ni semántica de Bash. |
| T-04 | EJECUTADA | `python3 audit/inspect_original.py` → `docker inspect` filtrado y `docker exec -u postgres ... psql` | 7 contenedores consultados, 6 clústeres originales con system_identifier distintos. Configuración, roles, HBA, catálogos y datos registrados en `raw/*_container.json`, `raw/*_sql.json`. Todas las consultas principales se rodearon con `BEGIN READ ONLY`. |
| T-05 | EJECUTADA | `docker version`, `docker compose version`; conexiones desde `sigtec-tools` con `PGSSLMODE=require` y `default_transaction_read_only=on` | Docker cliente/servidor 29.2.1, Compose 5.0.2; los seis hosts internos resuelven y permiten conectarse a sigtec como postgres por TLS. `raw/original_network_tls.log`. |
| T-06 | EJECUTADA | Consultas `version()`, `postgis_full_version()`, pg_settings, pg_hba_file_rules, pg_authid con salida booleana | PostgreSQL 17.12, PostGIS 3.5.4, wal_level logical, slots/senders 16/16, checksums on, SCRAM almacenado para postgres y sigtec_backup en seis nodos, TLS on. `raw/*_sql.json`, `raw/scram_corrected.json`. No se imprimieron verificadores ni contraseñas. |
| T-07 | EJECUTADA | Catálogos, `ST_IsValid`, `ST_IsEmpty`, `ST_SRID`, `ST_GeometryType`, `ST_Extent(ST_Transform(...,4326))`; listado de IDs | 40 tablas originales; tipos y SRID correctos; 0 geometrías inválidas/vacías o SRID incorrectos. 207 IDs actuales, 207 distintos: 205 de semilla y 2 del PITR previo. `raw/*_sql.json`, `raw/all_original_ids.json`. |
| T-08 | EJECUTADA | `bash scripts/setup.sh` en copia aislada, sin `.env` inicial | Falló antes de generar `.env` por revisar puertos predeterminados ocupados, pese a plantilla alternativa. Código 1, `raw/clean_setup.log`. F-04. |
| T-09 | EJECUTADA | `env COMPOSE_PROJECT_NAME=sigtec_audit_20261120 SIGTEC_PORT_CENTRAL=56430 ... SIGTEC_PORT_RECOVERY=56436 bash scripts/setup.sh` | Código 0; seis nodos desde volúmenes nuevos, imagen con etiqueta propia, nuevas credenciales y datos. Inicialmente usó caché de construcción; no se presenta como compilación sin caché. `raw/clean_setup_exported.log`. |
| T-10 | EJECUTADA | `docker compose --project-directory audit/lab -f audit/lab/compose.yaml build --no-cache pg-central` | Código 0; descarga del tarball, SHA-256, compilación e instalación de PostGIS y paquetes efectivos. `raw/uncached_build.log`. No se borró la imagen base ni el caché global de Docker. |
| T-11 | EJECUTADA | En laboratorio: `bash tests/run_tests.sh --full` | Código 0, **292 PASS / 0 FAIL SQL**, más controles de Docker/higiene/idempotencia/persistencia del ejecutor. Se inspeccionó el contenido de la suite. Se corrió antes de introducir anomalías adversas. `raw/lab_full_tests.log`. |
| T-12 | EJECUTADA | `python3 audit/second_setup.py` → segundo `bash scripts/setup.sh` completo | Código 0; hashes de todas las filas geográficas iguales, `.env` idéntico. También recreó los servicios del laboratorio con la imagen recompilada, conservando datos. `raw/second_setup.json`, `raw/second_setup.log`. |
| T-13 | EJECUTADA | `bash audit/restore_original.sh` en contenedor sin red; volúmenes originales montados `:ro` y copiados a `/backups` efímero | **7/7 directorios físicos** pasaron `pg_verifybackup` (San Carlos tiene dos); **6/6 lógicos** restaurados y **6/6 físicos** arrancados/promovidos desde el último respaldo por nodo. `raw/original_backups_retested.log`. Las bitácoras nuevas se escribieron en la copia efímera. |
| T-14 | EJECUTADA | En laboratorio: `logical_backup.sh all`, `physical_backup.sh all`, `logical_restore_test.sh all`, `physical_restore_test.sh all`, mediante Compose tools | Los cuatro comandos terminaron 0; seis nodos por tipo respaldados y restaurados. `raw/lab_logical_backups.log`, `raw/lab_physical_backups.log`, `raw/lab_logical_restores.log`, `raw/lab_physical_restores.log`. En Cartago se conservaron las anomalías introducidas por la prueba de IDs: estos verificadores no buscan duplicados entre tablas. |
| T-15 | EVIDENCIA EXISTENTE + EJECUTADA | Lectura de `evidence/pitr/pitr_20261120T172854Z.*`; `docker logs sigtec-pg-recovery-1`; `python3 audit/pitr_direct.py` | Se corroboró el PITR anterior con logs reales, timestamps SQL, A conservado/B excluido y original con ambos cambios. `raw/original_recovery_docker.log`, `raw/pitr_direct.json`. |
| T-16 | EJECUTADA | En laboratorio: `bash scripts/recovery/pitr_demo.sh san_carlos` | Código 0; corrida nueva **20261120T202335Z**, falla SIGKILL solo del campus temporal. A previo recuperado, B excluido, promoción a timeline 2, original del laboratorio con A modificado y B. `raw/lab_pitr.log`, `lab/evidence/pitr/pitr_20261120T202335Z.md`, `raw/pitr_direct.json`. La marca final falla separadamente: T-19. |
| T-17 | EJECUTADA | `python3 audit/adversarial.py`: tools con `SIGTEC_BACKUP_PASSWORD` deliberadamente inválida y `BACKUP_ROOT=/tmp/audit-negative-*` | Ambos scripts de respaldo devolvieron **0** y OK pese al rechazo de autenticación. **NO APROBADO**, F-01. `raw/adversarial.json`. |
| T-18 | EJECUTADA | Mismo instrumento: rol audit_editor sin permisos de secuencia; SET de mantenimiento; dos sesiones concurrentes | ID explícito permitido y **1000000043 duplicado** en puntos_interes/iluminacion después de ambos COMMIT. **NO APROBADO**, F-02. `raw/adversarial.json`. Solo laboratorio. |
| T-19 | EJECUTADA | `pitr_steps.sh marcar-recuperada san_carlos audit-marker-validation ...` | Código 1, error sintáctico en `:'run'`; la ejecución completa había ocultado ese error y declarado EXITOSA. La consulta directa confirmó ausencia de RECUPERADA. F-03, `raw/adversarial.json`, `raw/pitr_direct.json`. |
| T-20 | EJECUTADA | `integration_probe.sh`: aplicar plantilla en central del laboratorio y CREATE PUBLICATION dentro de BEGIN/ROLLBACK en San José | Plantilla crea 40 tablas destino. Las ocho tablas locales aparecen en pg_publication_tables; publicación de prueba revertida. `raw/integration_probe.log`. No se crearon suscripciones ni slots definitivos. |
| T-21 | EJECUTADA | `tests/container/test_template_central.sh` usando la imagen reconstruida sin caché | Código 0: los cinco esquemas × ocho tablas coinciden en columnas, tipos, NOT NULL, defaults, PK/CHECK y replica identity. `raw/uncached_image_template_test.log`; también pasó en T-11. |
| T-22 | EJECUTADA | En laboratorio: `bash scripts/backup/wal_retention.sh all --keep 2` | Código 0, solo simulación; inventario y corte calculados. No borró archivos. `raw/wal_retention_dry_run.log`. |
| T-23 | EJECUTADA / EXPANSIÓN, SIN BORRADO | `make -n wal-retention APPLY=0` | Expandió `--apply`. No se ejecutó el script resultante. F-05, `raw/configuration_probes.json`. |
| T-24 | EJECUTADA | Con laboratorio detenido y `.env` existente: `bash scripts/check_prereqs.sh`, y repetición con variables de puerto exportadas | Código 1 sin exportación, 0 exportando; prueba específica de F-04. `raw/configuration_probes.json`. |
| T-25 | EJECUTADA | `PGSSLMODE=disable psql_su central` en laboratorio | Conexión permitida, `pg_stat_ssl.ssl=false`. TLS no es obligatorio. F-06, `raw/adversarial.json`. |
| T-26 | ESTÁTICA | Comparación setup.ps1/setup.sh; inspección de Dockerfile, HBA, limpieza y documentación | Flujo PowerShell sin Bash no incorpora claves nuevas de plantilla; certificado autofirmado, dependencias Debian no fijadas exactamente, volúmenes en misma máquina y retención manual documentados. F-07/F-08/F-09 y límites del informe. |
| T-27 | EJECUTADA | `python3 audit/final_verify.py` | 69/69 archivos originales sin cambios; hashes de todas las filas geográficas de los cinco campus y recuperación idénticos al inicio; 0 valores secretos originales encontrados en otros archivos. `raw/final_integrity.json`. |
| T-28 | EJECUTADA | `docker compose --project-directory audit/lab -f audit/lab/compose.yaml --profile recovery stop` | Siete contenedores temporales detenidos, volúmenes conservados. Originales siguen operativos. `raw/lab_stop.log`, inventario de cierre. |

## PITR: comprobación temporal independiente

| Dato | Demostración original | Demostración de auditoría |
|---|---|---|
| Run | 20261120T172854Z | 20261120T202335Z |
| Base | physical/san_carlos/20261120T172854Z/data | physical/san_carlos/20261120T202335Z/data |
| Commit de A, UTC | 17:28:57.799862 | 20:23:39.092490 |
| Objetivo, UTC | 17:29:00.365787 | 20:23:41.550941 |
| Commit de B, UTC | 17:29:02.879970 | 20:23:43.971695 |
| A restaurado | ID 3000000050, descripción previa | ID 3000000050, descripción previa |
| B restaurado | Ausente | Ausente |
| Original correspondiente | A modificado y B presente | A modificado y B presente |
| Timeline original / recuperada | 1 / 2 | 1 / 2 |

Ambas cumplen A < objetivo < B. Los IDs coinciden numéricamente entre laboratorios porque son despliegues independientes con la misma semilla; los identificadores de corrida y los volúmenes son distintos. No se reutilizó el `pg-recovery` original. Las consultas de timestamps sobre A en el original muestran la versión actualizada por B; el commit original de A se comprobó sobre la versión preservada en la recuperada.

## Cobertura real y pendientes

**Comprobado en host macOS arm64:** instalación con alternativa para puertos, construcción sin caché de capas, dos instalaciones completas, suite, persistencia, respaldos, restauraciones, WAL, dos PITR corroborados y pruebas adversas. **Linux:** las herramientas de base de datos sí corrieron dentro de contenedores Linux; la instalación en un host Linux sigue NO EJECUTADA. **Windows/PowerShell/WSL/Git Bash:** NO EJECUTADA; compatibilidad probable por inspección, con F-07 identificado.

**No ejecutado:** PITR individual de los otros cinco nodos, replicación end-to-end entre nodos, rol definitivo de replicación, reincorporación completa, acceso real QGIS, cuentas finales, recuperación de toda la máquina Docker perdida, retención destructiva, 2PC y pruebas de disco lleno. Restaurar físicamente seis nodos no equivale a haber probado PITR temporal A/B en cada uno. El procedimiento común de PITR admite central/campus en su entrypoint, pero el demo automatizado solo acepta campus.

**Evidencia anterior revisada:** setup, imagen, versiones, suite 292/292, seis dump/restores y seis físicos/restores en `evidence/`. Su lectura no se contó como nueva ejecución. Se corroboraron funcionalmente los puntos centrales descritos arriba. No hay firma, commit o hash histórico que pruebe que todos los informes antiguos correspondan exactamente a cada archivo actual.

## Incidencias del instrumental de auditoría

`pdftotext` no estaba instalado y el Python de sistema no tenía lectores PDF; se usó el Python incluido con pypdf y pypdfium2. Un intento con PyMuPDF tampoco estaba disponible. La extracción señaló un objeto PDF con offset incorrecto, pero permitió leer el documento y se contrastaron visualmente los cuadros relevantes.

El sandbox inicialmente negó el socket Docker; el acceso posterior autorizado permitió completar las pruebas. Una consulta inicial del auditor para el prefijo SCRAM incluyó accidentalmente un espacio final y produjo `false`; fue corregida mediante `split_part(rolpassword,chr(36),1)`, con `true` para ambas cuentas en todos los nodos. Ese resultado inicial no se clasificó como defecto del proyecto y se conserva para trazabilidad.

Los scripts de auditoría guardados en `audit/` son instrumentos diagnósticos: algunos crean roles/filas exclusivamente en el laboratorio y no deben apuntarse al despliegue original. Sus comandos y las salidas JSON permiten revisar los resultados sin repetir las escrituras.

La inspección final adicional guardó las funciones y ACL reales en `raw/original_function_definitions.json` (seis consultas sin errores), procesos en `raw/original_postgres_processes.txt` y estados en `raw/original_final_status.txt` / `raw/lab_final_status.txt`. Un primer `docker top` omitió PID y fue rechazado por el parser del daemon; se repitió con `-eo pid,user,args`, observando PostgreSQL bajo UID 999. Se conservaron 15 volúmenes del laboratorio (`raw/lab_preserved_volumes.txt`).
