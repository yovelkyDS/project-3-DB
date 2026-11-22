# Pruebas de regresión de la remediación

Todas las ejecuciones son del 20 nov 2026 (macOS arm64, Docker 29.2.1, Compose 5.0.2).
Las evidencias nuevas están en `remediation/evidence/` mediante `SIGTEC_EVIDENCE_DIR`; las
evidencias originales (`evidence/`) y la auditoría (`audit/`) no se modificaron (sección 6).

## 1. Entornos

| Entorno | Descripción |
|---|---|
| Laboratorio | `remediation/lab/`: copia del proyecto con `COMPOSE_PROJECT_NAME=sigtec_remed`, puertos 57430–57436, `.env` y volúmenes propios (`sigtec_remed_*`). `remediation/scripts/sync_lab.sh` copia el código corregido (no copia `.env`). |
| Clústeres temporales | Dentro del contenedor efímero `sigtec-tools` (`test_ids_aislado.sh`, restauraciones): se destruyen al terminar. |
| Originales | Proyecto `sigtec`, seis nodos + `pg-recovery`. **No** se reconstruyeron ni se borraron volúmenes. |

## 2. Secuencia ejecutada

| # | Paso | Entorno | Resultado | Evidencia |
|---|---|---|---|---|
| 0 | Línea base: hashes de 59 archivos del proyecto; carpeta no es repositorio git | — | registrado | `evidence/00_baseline/` |
| 1 | Reproducción de F-01/F-02 con el código auditado | laboratorio | F-01 lógico y físico, F-02a, F-02b **reproducidos** | `evidence/01_reproduccion_prefix/` |
| 1b | Instalador con puertos alternativos sin exportar (F-04) | laboratorio | rc=1 (reproducido); exportados rc=0 | `evidence/00_baseline/lab_prefix_setup*.log` |
| 2 | `test_backup_failures.sh` | laboratorio | 36 PASS / 0 FAIL | `evidence/02_respaldos/lab_test_backup_failures.log` |
| 3 | `test_backup_host_paths.sh` | laboratorio | 10 PASS / 0 FAIL | `evidence/02_respaldos/lab_test_backup_host_paths.log` |
| 4 | 0103 con un duplicado real en los datos | laboratorio | abortó (rc=3), nada aplicado, datos intactos | `evidence/03_identificadores/lab_migracion_con_duplicado.log` |
| 5 | Resolver el duplicado de prueba y aplicar 0103 | laboratorio | aplicada en 5 campus; registro = objetos | `evidence/03_identificadores/lab_migracion_resuelta.log` |
| 6 | `test_ids_aislado.sh` | clústeres temporales | 272 PASS / 0 FAIL | `evidence/03_identificadores/lab_test_ids_aislado.log` |
| 7 | Reproducción tras la corrección | laboratorio migrado | todos **no reproducidos** | `evidence/04_reproduccion_postfix/` |
| 8 | `run_tests.sh --full` | laboratorio migrado | 392 SQL + 36 + 272, todas pasaron | `evidence/05_lab_regresion/tests/` |
| 9 | Instalación limpia (`clean.sh --yes` del laboratorio → `setup.sh` sin puertos exportados → `run_tests.sh --full` → `make backup` → `make restore-test` → `pitr_demo.sh san_carlos` → `make wal-retention`) | laboratorio | `PIPELINE_EXIT=0`; 733 PASS / 0 FAIL; 6 VÁLIDA + 6 RECUPERABLE; PITR EXITOSA | `evidence/06_lab_instalacion_limpia/` |
| 10 | Duplicados en los originales (solo lectura) | originales | 207 objetos, 0 repetidos entre capas | `evidence/07_original_pre_migracion/duplicados_previos.txt` |
| 11 | `make backup` + `make restore-test` **antes** de migrar | originales | 12 copias validadas; 6 VÁLIDA + 6 RECUPERABLE | `evidence/07_original_pre_migracion/` |
| 12 | `make migrate` (0103) | originales | 41/41/43/41/41 ids registrados | `evidence/08_original_migracion/migrate.log` |
| 13 | `run_tests.sh --full` | originales | 732 PASS / 1 FAIL (`repo.sin_rutas_absolutas`, ver 4) | `evidence/09_original_post_migracion/tests/tests_20261120_152609.log` |
| 14 | `make verify`, `make backup`, `make restore-test`, `make versions`, `make recovery-status` | originales | todos rc=0; `estado_ids = OK` ×5; 6 VÁLIDA + 6 RECUPERABLE | `evidence/09_original_post_migracion/pipeline.log`, `versions.txt` |
| 15 | `run_tests.sh --full` tras corregir 13 | originales | **733 PASS / 0 FAIL** | `evidence/09_original_post_migracion/tests/tests_20261120_152841.log` |
| 16 | Reproducción final | laboratorio limpio | todos **no reproducidos** | `evidence/10_reproduccion_final/` |
| 17 | Hashes de `audit/` (133 archivos) y comprobación de que ni `audit/` ni `evidence/` cambiaron desde la línea base | — | ningún archivo modificado | `evidence/11_cierre/` |

## 3. Comparación de la suite

| Sección | Antes (auditoría / `evidence/tests/tests_20261120_112808.log`) | Después (originales, paso 15) |
|---|---|---|
| [1] contenedores, red, volúmenes | 25 | 25 |
| [2] SQL y PostGIS | 292 | 392 (292 + 100 de `40_registro_ids.sql`) |
| [2b] F-01 respaldos fallidos | — | 36 |
| [2b] F-02 ids, concurrencia, mantenimiento | — | 272 |
| [3]–[5] higiene, idempotencia, persistencia | 8 | 8 |
| **Total** | **325 PASS / 0 FAIL** | **733 PASS / 0 FAIL** |

Las 292 pruebas originales siguen pasando sin cambios en su código; ninguna se eliminó ni se
debilitó. `tests/sql/10…30` no se modificaron.

## 4. Fallos encontrados durante la regresión

| Paso | Fallo | Causa | Acción |
|---|---|---|---|
| 13 | `repo.sin_rutas_absolutas`: `audit/AUDIT_REPORT.md` | La comprobación de higiene recorría `audit/`, que contiene rutas del equipo del auditor y no se puede modificar. Además, `reproduce_audit_defects.sh` imprimía la ruta absoluta del laboratorio. | `tests/run_tests.sh` excluye `audit/` (igual que ya excluía `evidence/`); el script imprime una ruta relativa; la línea 1 de los dos registros de reproducción (01 y 04) se cambió a ruta relativa (`evidence/11_cierre/NOTA_RUTAS.txt`). Repetido en el paso 15: PASS. |
| Desarrollo | 2 FAIL en `test_ids_aislado.sh` (concurrencia) | Las sesiones en segundo plano se lanzaban dentro de un pipeline y `wait` no las esperaba | `bg` recibe un archivo SQL y se invoca como orden simple; se añadió la comprobación de solapamiento (`pg_stat_activity` = 8). |
| Desarrollo | Casos de artefactos dañados omitidos sin FAIL | Variable reutilizada | Variable propia `P`; una entrada faltante registra FAIL. |

## 5. PITR

* **Laboratorio (instalación limpia):** San Carlos, cambio A antes del objetivo, cambio B después,
  falla simulada (`kill`), recuperación en `pg-recovery` aislada: A presente, B ausente (inserción
  y actualización), marca RECUPERADA registrada, `A < objetivo < B` comprobado en PostgreSQL,
  promovida, línea de tiempo 2, `estado_ids = OK` en la instancia recuperada (42 objetos), nodo
  original intacto. Resultado **PITR EXITOSA** (`evidence/06_lab_instalacion_limpia/pitr/`).
* **Originales:** **no se repitió**. `pitr_demo.sh` requiere `--reset` cuando `pg-recovery` ya
  existe, lo que elimina su volumen; la instrucción prohíbe eliminar volúmenes existentes.
  La evidencia PITR original (`evidence/pitr/`) se conserva. `make recovery-status` sobre la
  instancia existente: 8 capas OK, y "registro global de identificadores no disponible: datos
  anteriores a la migración 0103" (esperado).

## 6. Integridad de lo que no debía cambiar

* `find audit evidence -newer remediation/evidence/00_baseline/pre_fix_hashes.txt` → vacío.
* `remediation/evidence/11_cierre/audit_hashes.txt`: SHA-256 de los 133 archivos de `audit/`
  al cierre.
* Archivos del proyecto que sí cambiaron respecto de la línea base: exactamente los listados en
  `REMEDIATION_REPORT.md` §3 (`shasum -a 256 -c remediation/evidence/00_baseline/pre_fix_hashes.txt`).
* Volúmenes originales `sigtec_pgdata_*`, `sigtec_walarchive_*`, `sigtec_backups` presentes; los
  del laboratorio de la auditoría (`sigtec_audit_20261120_*`) también.
* Nuevos respaldos de los originales: directorios nuevos con marca de tiempo; ningún respaldo
  anterior se sobrescribió ni se eliminó (`wal-retention` solo se ejecutó en simulación).

## 7. No verificado

* Instalador PowerShell (`setup.ps1`) y anfitriones Windows/Linux: no ejecutados.
* PITR sobre los nodos originales (ver 5).
* Escrituras concurrentes durante un respaldo (F-09): no probadas.
* Reincorporación de un nodo recuperado a la replicación: corresponde al Integrante 2.
