# Pruebas ejecutadas — segunda auditoría

Fecha: 20 noviembre 2026; host macOS arm64, zona America/Costa_Rica. Timestamps Z/+00 en los registros son UTC. Los comandos parten de la raíz del proyecto. **Ejecutada** significa ejecutada durante esta segunda auditoría; **estática** y **evidencia anterior** no se cuentan como pruebas funcionales nuevas.

## Registro de ejecución

| ID | Modalidad y autoría | Instrumento / comando | Resultado |
|---|---|---|---|
| RT-01 | Propio, ejecutado | Comparación/hash de `audit/lab` y raíz; raíz/laboratorio | 20 archivos código/Makefile distintos o nuevos; fuentes operativas raíz/lab iguales. `raw/source_diff.patch`, `source_changes.json`, `lab_source_equivalence.json` |
| RT-02 | Propio, ejecutado; solo lectura | `python3 audit/reaudit/probes/independent.py inventory before` y `after` | 6 clústeres activos por proyecto, versiones, IDs, hashes de filas, imágenes/binarios y volúmenes. `inventory_*.json` |
| RT-03 | Propio, ejecutado con fuentes originales | Scripts originales de `audit/lab/scripts` montados RO en contenedor, contraseña errónea, salida temporal | F-01 original reproducido: lógico rc0/publicados1, físico rc0/publicados1; ambos OK inválidos. `F01_original_baseline.json` |
| RT-04 | Propio, ejecutado con código remediado | `independent.py f01` | Lógico rc1/publicados0/ERROR; físico rc1/publicados0/ERROR; sin secreto en diagnóstico. `f01_independent.json` |
| RT-05 | Suite de remediación, reejecutada por auditor | `SIGTEC_EVIDENCE_DIR=.../audit/reaudit/raw bash remediation/lab/tests/run_tests.sh --full` | rc0, 733 PASS/0 FAIL. Se reiniciaron solo seis contenedores del laboratorio. `full_suite_console.log`, `raw/tests/*.log` |
| RT-06 | Conteo independiente | Recuento de líneas PASS/FAIL y etiquetas del log de RT-05 | 392 SQL + 36 respaldo + 272 IDs + 33 host = 733. Quince etiquetas repetidas entre suites. `suite_count.json` |
| RT-07 | Propio, ejecutado | `independent.py ids` | Editor: automático permitido sin USAGE de secuencia; GUC explícito, autorización, registro, desactivar triggers, replica y autoGRANT rechazados 42501. `ids_independent.json` |
| RT-08 | Propio, conexiones distintas | RT-07, carrera con mantenimiento | ID 1000000067: primera confirma, segunda espera 3,84 s y falla 23505; una fila. ID 1000000068: primera revierte, segunda espera 3,85 s y confirma; registro coherente |
| RT-09 | Propio, conexiones distintas | RT-07, seis PID superpuestos/30 filas por conexión | 180 inserciones; al final 224 objetos/224 IDs/0 sin registro en Cartago. Roles de prueba retirados. Filas solo en laboratorio |
| RT-10 | Suite de remediación, reejecutada por auditor | Incluida en RT-05: `test_ids_aislado.sh campus` | 272 PASS: 8 conexiones × 8 capas por campus; migración limpia, permisos, commit/rollback, eliminación, reinicio, dump/restore, publicación; actualización desde 0102 con duplicado aborta sin instalación parcial |
| RT-11 | Suite de remediación, reejecutada por auditor | Incluida en RT-05: `test_backup_failures.sh` | 36 PASS: contraseñas inválidas en seis nodos, no escribible, servidor caído simulado, archivo parcial, corrupción y positivos con seis restauraciones por tipo |
| RT-12 | Script de remediación, reejecutado por auditor | `bash remediation/scripts/test_backup_host_paths.sh remediation/lab` | 10 PASS/0 FAIL; make rc2 ante autenticación inválida, no etapa física dependiente ni nuevos publicados. Tras resincronizar contraseña solo del central del laboratorio, backup rc0. `host_backup_paths.log` |
| RT-13 | Propio, restauraciones reales | `independent.py original_restores` | 6 originales lógicos restaurados y 6 físicos promovidos con fd04; `pg_verifybackup` sobre las seis físicas. Contenedor sin red, backups/WAL originales RO y copiados a /tmp. `original_restores.log` |
| RT-14 | Evidencia previa corroborada; no corrida propia | Lectura de `remediation/evidence/06.../pitr`, consultas SQL y logs existentes | Corrida 20261120T212428Z: A previo en recuperación/B excluido; marcas A/RECUPERADA; source A modificado+B. `integration_catalogs.json:prior_pitr`, `prior_pitr_container.log` |
| RT-15 | Propio, PITR nuevo | `independent.py pitr`, pasos SQL reales y contenedor nuevo | A < objetivo < B en SQL, WAL real, SIGKILL al San Carlos del laboratorio, A anterior/B fuera, promoción timeline2, 44/44/0 registro. `pitr_parameters.json`, `pitr_independent.json`, `pitr_new_container.log` |
| RT-16 | Propio, resolución de incidencia de arnés | `independent.py marker_followup` | Script real `marcar-recuperada` rc0 y marcas A/RECUPERADA almacenadas en recuperación nueva. `marker_followup_independent.json` |
| RT-17 | Propio, inyección aislada | Función `t()` extraída del script real; `tools()` de prueba devuelve 37 | CAPTURED_RC=37. No se ejecutó el demo completo que exige reset. `F03_pipeline_failure.json` |
| RT-18 | Propio, ejecutado sin exportar puertos | `check_prereqs.sh` del laboratorio con proyecto vacío temporal | Detectó ocupados 57430–57436 leídos de .env, rc1 esperado; no buscó 55430. `residual_independent.json` |
| RT-19 | Propio, seguro/no borrado | `make -C remediation/lab wal-retention APPLY=0`; make inválido; expansión con -n | 0 simuló, inválido rc2, 1 revisado sin ejecutar --apply. `retention_apply0.log`, `residual_independent.json` |
| RT-20 | Propio, transporte real | psql TCP `sslmode=disable` en central del laboratorio | Permitido, ssl=false; F-06 pendiente. `residual_independent.json` |
| RT-21 | Estática | `setup.ps1` frente a `setup.sh` | F-07 sigue presente; Windows no ejecutado |
| RT-22 | Propio, intercalado controlado | Wrapper temporal de pg_dump + escritor desde otra conexión durante ventana previa al manifiesto | F-09 reproducido: pg_restore correcto, capa 98 vs manifiesto99, secuencia248 vs249, restore-test rc1, registro/spatial/triggers correctos. `residual_independent.json` |
| RT-23 | Propio, solo lectura/catálogo | `independent.py integration` | Firmas de 5 campus iguales en originales y laboratorio; ACL y 24 triggers comprobados; publicación reversible de 8 tablas, sin ops. `integration_catalogs.json`, `integration_independent.json` |
| RT-24 | Propio, solo lectura | Consultas originales con `BEGIN READ ONLY` | Cartago41/SanJosé41/SanCarlos43/Alajuela41/Limón41; IDs distintos, 0 sin registro, 0 prefijos incorrectos. `original_registry_checks.json` |
| RT-25 | Propio, ejecutado sin conexiones SQL por destino inválido | `scripts/db/migrate.sh recovery`; `make -C remediation/lab migrate NODE=recovery` | **nodo inválido: recovery; ambos rc0.** RA-01. `migrate_recovery_probe.log`, `make_migrate_recovery.log` |
| RT-26 | Propio, reproducción en copia de original | Dump RO de `sigtec-pg-recovery-1`; `probes/legacy_recovery.sh` en contenedor sin red | Sin0103/sinregistro; editor sin USAGE secuencia; dos conexiones confirmaron ID3000000083, 2 filas. rc0 del arnés significa reproducción esperada, no aprobación. `legacy_recovery_reproduction.json` |
| RT-27 | Propio, sintaxis y secretos | bash -n y escaneo de valores sin imprimirlos | 29 archivos shell sin error; ningún valor secreto original encontrado fuera de .env. `preservation_files.json` |
| RT-28 | Propio, preservación | Comparar SHA-256 de 322 archivos, snapshots SQL y listas de volúmenes | Sin archivos previos alterados, datos originales iguales en 7 servicios y sin volumen preexistente eliminado. `final_integrity.json` |

## Cobertura y límites de las 733 aserciones

Las 292 aserciones SQL originales siguen en la suite; las 100 nuevas se distribuyen en 20 por campus. Las 272 de identificadores recorren cinco clústeres temporales y una actualización desde 0102. Las 36 de respaldos incluyen comprobaciones agrupadas sobre seis nodos, por lo que ni siquiera cada PASS equivale necesariamente a una operación. La cuenta 733 es correcta como número de líneas de aserción del ejecutor.

La nueva exclusión `audit/` se usa para rutas absolutas de evidencia externa. No excluye las pruebas funcionales. El escaneo de secretos continúa recorriendo los otros archivos; esta auditoría lo hizo también sobre la raíz sin excluir el material de auditoría. La ejecución de 733 se hizo sobre el laboratorio, no sobre originales, porque --full migra/carga/reinicia. Las afirmaciones sobre los originales se basan en lecturas directas y restauraciones aisladas.

La suite no contempla el destino recovery ni la actualización de una recuperación física pre-0103. Un clúster temporal creado desde cero con 0103 y un restore de ese clúster no cubren esa transición. Tampoco incorpora la carrera F-09. Estos dos huecos se demostraron aquí; el número verde no se usa como aprobación global.

Otras limitaciones: idempotencia compara conteos/suma de IDs, no todas las columnas, y la lista `migrate && seed` puede perder un fallo de migrate; la búsqueda de `latest` no prueba inmutabilidad de etiqueta; el restore físico actual no compara explícitamente la secuencia con su metadato pese a mencionarla en el encabezado. No se observó fallo de datos por esas limitaciones en los restores ejecutados. La auditoría comparó adicionalmente hashes de todo el contenido geográfico original.

No se ejecutaron Windows/Linux como host, QGIS, auth, replicación completa, 2PC, reincorporación final, PITR temporal en cada campus, desastre total del host, retención con borrado ni construcción nueva sin caché. No se certifican por inferencia. La suite sí inició clústeres limpios temporales con migraciones/semilla, pero eso no equivale a repetir el instalador completo de seis nodos en otro host.

## Incidencias del instrumental y resolución

Se conservan resultados fallidos del auditor para no confundirlos con defectos del proyecto:

- El primer intento PITR generó un respaldo y el lector propio intentó tomar la última línea de stdout vacío; el script de respaldo escribe diagnóstico en stderr. Se corrigió solo el lector en `probes/` y se repitió antes de detener nodos.
- En la corrida PITR nueva el acceso a la marca usó `docker compose run --add-host`, opción no admitida. La recuperación de datos sí funcionó; `pitr_independent.json` conserva `F03_marker_actual_script=false` con `unknown flag`. Se sustituyó esa parte del arnés por una entrada /etc/hosts dentro del tools efímero y se ejecutó el mismo script real: `marker_followup_independent.json` demuestra marca almacenada. El resultado fallido inicial no se presenta como fallo de F-03 ni se borra. También se corrigió un KeyError del resumidor que mezclaba pasos con aserciones.
- La primera inicialización del clúster de copia antigua agrupó CREATE DATABASE con CREATE ROLE en un único -c, lo que PostgreSQL rechazó. Ocurrió antes de restaurar; se conserva `legacy_recovery_instrument_attempt1.json`. Se separaron las órdenes del arnés y la repetición confirmó RA-01.
- El sandbox inicialmente no permitía el socket Docker; el acceso autorizado posterior permitió completar las verificaciones. No hubo rechazo de auto-review que dejara verificaciones pendientes.

Los scripts de `probes/` son instrumentos de auditoría que escriben en laboratorios. No deben apuntarse sin inspección a datos activos ni repetirse a ciegas: la corrida PITR conserva su contenedor/volúmenes y no los resetea. No se realizaron cambios correctivos al código del proyecto.
