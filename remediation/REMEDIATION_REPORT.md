# Informe de remediación — SIG-TEC, Integrante 1

Fecha: 20 nov 2026 · Entrada: auditoría de Codex (`audit/`, veredicto **NO APROBADO** por F-01 y
F-02) · Alcance: corregir los dos defectos bloqueantes con cambios mínimos y probados; además
F-03, F-04, F-05 y la parte documental de F-08.

**Veredicto de la remediación: CORRECCIONES VERIFICADAS.**
F-01 y F-02 se reprodujeron con el código auditado, se corrigieron y dejaron de reproducirse en
un laboratorio aislado y en la instalación limpia; la migración se aplicó a los nodos originales
tras respaldarlos, y la suite completa pasó en ellos (733/733). Esto no equivale a aprobación
académica; las limitaciones están en la sección 9.

## 1. Causas

| Hallazgo | Causa raíz |
|---|---|
| F-01 falso éxito de respaldo | `backup_node` se ejecutaba dentro de `if ! ( set -e; … )`. Bash ignora `errexit` en contextos condicionales, así que un `pg_dump`/`pg_basebackup` fallido no detenía la función: se escribía el manifiesto, se registraba `OK`, se devolvía 0 y el directorio quedaba publicado con nombre definitivo. |
| F-02 ids | (a) El GUC `sigtec.permitir_id_explicito` lo puede asignar cualquier rol y el disparador era `SECURITY DEFINER`, por lo que no había autorización real. (b) La unicidad entre capas se comprobaba con ocho `SELECT EXISTS`, que no ven filas no confirmadas de otras transacciones. |
| F-03 | La marca RECUPERADA usaba `psql -c` con variables `:'run'`, que `-c` no interpola (error de sintaxis); la función `t()` del demo terminaba en `grep` sin preservar el código del comando, y las comprobaciones del original y del orden temporal no eran aserciones. |
| F-04 | `check_prereqs.sh` solo usaba variables exportadas, no `.env`. |
| F-05 | `APPLY=0` se trataba como "definido" y aplicaba el borrado. |

## 2. Soluciones

* **F-01:** `run_step` ejecuta cada nodo como instrucción simple con `set -Eeuo pipefail`; cada
  comando crítico se comprueba explícitamente; directorio de trabajo oculto `.en-curso-*`;
  validación (lectura completa del dump y TOC; `pg_verifybackup`); publicación atómica con
  `mv -T`; ante un fallo, `.fallido-*` sin carga útil, `ERROR` en la bitácora, diagnóstico de
  PostgreSQL sin secretos y código ≠ 0. Detalle: [BACKUP_FIX.md](BACKUP_FIX.md).
* **F-02:** migración nueva `0103`: registro `ops.identificadores_globales` con `PRIMARY KEY (id)`
  alimentado por un disparador `AFTER INSERT` (`ON CONFLICT DO NOTHING` + `23505`); asignación
  `SECURITY INVOKER`; ids explícitos solo para miembros del rol `NOLOGIN`
  `sigtec_mantenimiento_id`; ids eliminados no reutilizables; aborta sin cambios si encuentra
  duplicados. Detalle: [GLOBAL_ID_FIX.md](GLOBAL_ID_FIX.md).
* **F-03/F-04/F-05:** ver [BACKUP_FIX.md](BACKUP_FIX.md) §6.

## 3. Archivos modificados y nuevos

Modificados (verificable con `shasum -a 256 -c remediation/evidence/00_baseline/pre_fix_hashes.txt`):

| Archivo | Motivo |
|---|---|
| `scripts/lib/db.sh` | `run_step`; `psql_backup -w` |
| `scripts/lib/backup.sh` | publicación atómica, validación, diagnóstico |
| `scripts/backup/logical_backup.sh`, `physical_backup.sh` | F-01 |
| `scripts/backup/logical_restore_test.sh`, `physical_restore_test.sh` | `run_step`; comprobación del registro |
| `scripts/db/verify.sh` | comprobación del registro |
| `scripts/lib/host.sh` | `SIGTEC_EVIDENCE_DIR` (evidencias separadas) |
| `scripts/recovery/pitr_steps.sh`, `pitr_demo.sh` | F-03 |
| `scripts/check_prereqs.sh` | F-04 |
| `Makefile` | F-05 |
| `sql/templates/ajustar_secuencia_tras_recuperacion.sql` | considera el registro |
| `tests/run_tests.sh` | sección `[2b]`; la higiene excluye `audit/` |
| `tests/container/run_sql_tests.sh` | ejecuta `40_registro_ids.sql` |
| `docs/BACKUP_RECOVERY.md`, `docs/INTEGRATION.md`, `docs/DATA_DICTIONARY.md`, `docs/DEPENDENCIES.md`, `README.md` | documentación |

Nuevos: `sql/migrations/campus/0103_registro_identificadores.sql`,
`sql/checks/verificar_registro_ids.sql`, `tests/sql/40_registro_ids.sql`,
`tests/container/test_backup_failures.sh`, `tests/container/test_ids_aislado.sh`,
`remediation/` (documentos, `scripts/`, `lab/`, `evidence/`).

No modificados: migraciones 0001, 0002, 0101, 0102; esquema de capas; datos de prueba;
`compose.yaml`; configuración de PostgreSQL; Dockerfile; versiones; `audit/`; `evidence/`.

## 4. Migraciones ejecutadas

| Dónde | Migración | Resultado |
|---|---|---|
| Laboratorio, con un duplicado deliberado | `campus/0103_registro_identificadores` | abortó (rc=3), sin cambios |
| Laboratorio, tras resolverlo | idem | aplicada en 5 campus |
| Laboratorio, instalación limpia | todas (0001…0103) | aplicadas por `setup.sh` |
| **Originales** (20 nov 2026 15:26 −0600), después de respaldos validados | `campus/0103_registro_identificadores` | aplicada: Cartago 41, San José 41, San Carlos 43, Alajuela 41, Limón 41 ids registrados; sin conflictos |

`pg-recovery` original no se migró (instancia de la demostración PITR, datos previos a 0103).

## 5. Resultados de pruebas: originales y nuevos

| Suite | Antes (auditoría) | Después — laboratorio limpio | Después — originales |
|---|---|---|---|
| SQL/PostGIS | 292/292 | 392/392 | 392/392 |
| Respaldos fallidos (F-01) | — | 36/36 | 36/36 |
| Ids, concurrencia, mantenimiento (F-02) | — | 272/272 | 272/272 |
| Infraestructura, higiene, idempotencia, persistencia | 33/33 | 33/33 | 33/33 |
| **Total `run_tests.sh --full`** | **325/325** | **733/733** | **733/733** |
| Reproducción adversaria F-01/F-02 | 4 defectos reproducidos | 0 reproducidos (+F-02c autorizado: 1 sola fila) | no se ejecuta sobre originales (crea roles y filas) |

La primera ejecución completa sobre los originales dio 732/733: la comprobación de higiene
marcó rutas absolutas dentro de `audit/` (solo lectura). Se corrigió su alcance y se repitió:
733/733. Detalle en [REGRESSION_TESTS.md](REGRESSION_TESTS.md).

## 6. Respaldos, restauración y PITR

| Ejecución | Lógicos | Físicos | Restauración |
|---|---|---|---|
| Originales antes de 0103 | 6 OK validados | 6 OK verificados | 6 VÁLIDA + 6 RECUPERABLE |
| Originales después de 0103 | 6 OK validados | 6 OK verificados | 6 VÁLIDA + 6 RECUPERABLE (incluye registro, 24 disparadores) |
| Laboratorio limpio | 6 OK | 6 OK | 6 VÁLIDA + 6 RECUPERABLE |
| Negativos (laboratorio y suite) | rc ≠ 0, nada publicado | rc ≠ 0, nada publicado | — |

**PITR:** EXITOSA en el laboratorio limpio (San Carlos; A presente, B ausente, orden temporal y
marca comprobados en PostgreSQL, línea de tiempo 2, registro de ids consistente, original intacto):
`evidence/06_lab_instalacion_limpia/pitr/pitr_20261120T212428Z.md`. **No repetido en los
originales** (requiere eliminar el volumen de `pg-recovery`). `make wal-retention` solo en simulación.

## 7. Preparación para el Integrante 2

Sin cambios en tablas publicables, parámetros ni plantillas; `global.plantilla_central_compatible`
sigue pasando. Requisitos nuevos: insertar sin `id`, no publicar `ops`, no replicar hacia los
esquemas originales, migrar `pg-recovery` antes de reincorporarlo. Ver
[INTEGRATION_IMPACT.md](INTEGRATION_IMPACT.md). La entrega del Integrante 1 deja de estar
bloqueada por F-01/F-02 si la nueva auditoría lo confirma.

## 8. Efecto lateral: identidad de la imagen

La instalación limpia del laboratorio construyó la Dockerfile con la misma etiqueta
`sigtec/postgis:17.12-3.5.4`. Con el almacén containerd de Docker 29.2.1, el registro de la
imagen auditada (`cc0beda0…`) desapareció al reasignarse la etiqueta (ahora `fd04b3df…`). Los
contenedores originales siguen ejecutando su imagen y no se afectaron; si se recrean, usarán
`fd04b3df…`, misma fuente y digest base: PostgreSQL 17.12 con binario idéntico, PostGIS 3.5.4
compilado de la misma fuente fijada (binario distinto: la compilación no es reproducible bit a
bit). No fue posible restaurar la etiqueta. Prevención aplicada: el laboratorio usa
`SIGTEC_IMAGE=sigtec-remed/postgis:17.12-3.5.4`. Evidencia:
`evidence/09_original_post_migracion/NOTA_IMAGEN.txt`.

## 9. Limitaciones restantes

* F-06, F-07 y F-09: pendientes (no bloqueantes según la auditoría).
* Superusuarios pueden eludir el registro deshabilitando disparadores; se detecta, no se impide.
* PITR no repetido sobre los nodos originales.
* Windows, Linux y `setup.ps1`: no probados.
* Reincorporación a la replicación: no demostrada (Integrante 2).
* La carpeta no es un repositorio git: la trazabilidad de cambios es por hashes
  (`evidence/00_baseline/pre_fix_hashes.txt`).

## 10. Instrucciones para la nueva auditoría

Ver [READY_FOR_REAUDIT.md](READY_FOR_REAUDIT.md).
