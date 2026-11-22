# Preparado para nueva auditoría

**Estado de la remediación: CORRECCIONES VERIFICADAS** para F-01 y F-02 (defectos bloqueantes),
con las limitaciones de la sección 4. Esto **no** es una declaración de aprobación académica: la
decisión corresponde a la nueva auditoría.

## 1. Qué revisar

| Hallazgo | Documento | Código principal |
|---|---|---|
| F-01 | [BACKUP_FIX.md](BACKUP_FIX.md) | `scripts/lib/db.sh` (`run_step`), `scripts/lib/backup.sh`, `scripts/backup/*.sh` |
| F-02 | [GLOBAL_ID_FIX.md](GLOBAL_ID_FIX.md) | `sql/migrations/campus/0103_registro_identificadores.sql` |
| F-03, F-04, F-05 | [BACKUP_FIX.md](BACKUP_FIX.md) §6 | `scripts/recovery/pitr_*.sh`, `scripts/check_prereqs.sh`, `Makefile` |
| Pruebas | [REGRESSION_TESTS.md](REGRESSION_TESTS.md) | `tests/sql/40_registro_ids.sql`, `tests/container/test_backup_failures.sh`, `tests/container/test_ids_aislado.sh` |
| Integración | [INTEGRATION_IMPACT.md](INTEGRATION_IMPACT.md) | `docs/INTEGRATION.md` |

## 2. Cómo verificar (sin tocar los originales)

Use un laboratorio con nombre de proyecto, puertos e imagen propios. El laboratorio de la
remediación ya existe en `remediation/lab/` (proyecto `sigtec_remed`, puertos 57430–57436,
imagen `sigtec-remed/postgis:17.12-3.5.4`) y está en ejecución.

1. Reproducir los escenarios de la auditoría (crea un rol y filas de prueba **en el laboratorio**):

   ```bash
   bash remediation/scripts/reproduce_audit_defects.sh remediation/lab /tmp/reaudit_reproduccion.log
   ```

   Esperado: `DEFECTO NO REPRODUCIDO` en F-01 lógico, F-01 físico, F-02a, F-02b y F-02c.

2. Suites nuevas y completas (desde la carpeta del laboratorio):

   ```bash
   cd remediation/lab && bash tests/run_tests.sh --full
   ```

   Esperado: `RESUMEN: 392 PASS`, `RESUMEN respaldos: 36 PASS`, `RESUMEN identificadores: 272 PASS`,
   `RESULTADO: todas las pruebas pasaron`.

3. Rutas del anfitrión (`make backup` se detiene ante un fallo):

   ```bash
   bash remediation/scripts/test_backup_host_paths.sh remediation/lab
   ```

4. Opcional: el script adversario de la auditoría (`audit/adversarial.py`, no ejecutado por la
   remediación; puede requerir adaptar nombres de proyecto y puertos) contra un laboratorio
   nuevo. Comportamiento esperado: `rc ≠ 0` y ningún directorio publicado en F-01, `42501` para el rol sin
   privilegios y, como máximo, una fila confirmada en la carrera.

5. Instalación limpia: `remediation/evidence/06_lab_instalacion_limpia/pipeline.log` muestra la
   secuencia completa; para repetirla en el laboratorio:
   `cd remediation/lab && bash scripts/clean.sh --yes && bash scripts/setup.sh` (solo afecta a
   `sigtec_remed_*`).

En los originales solo lectura: `make verify` (`estado_ids = OK` en los cinco campus) y
`make test` (no deja filas ni roles: las pruebas SQL se revierten y las suites nuevas usan
clústeres temporales y `/tmp`; solo avanza las secuencias, que no son transaccionales).

## 3. Puntos que conviene que la auditoría intente romper

* Carrera con dos roles **autorizados** y el mismo id (la segunda sesión debe esperar y fallar).
* Un rol con `INSERT` que intente: `SET sigtec.permitir_id_explicito`, llamar a
  `sigtec_id_autorizar_explicito`, escribir en `ops.identificadores_globales`,
  `ALTER TABLE … DISABLE TRIGGER`, `SET session_replication_role`.
* Respaldo con red caída, destino lleno o de solo lectura, archivo truncado o manifiesto ausente.
* Aplicar 0103 sobre datos con un id repetido (debe abortar sin cambios).

## 4. Limitaciones conocidas (declaradas, no ocultas)

| Tema | Estado |
|---|---|
| Superusuario/dueño puede deshabilitar disparadores o vaciar tablas | Capacidad de PostgreSQL no revocable; detectado por `make verify`. |
| PITR en los originales | No repetido (requiere eliminar el volumen de `pg-recovery`). Verificado en el laboratorio limpio. |
| F-06 (TLS opcional en el servidor), F-07 (PowerShell no agrega claves nuevas a un `.env` existente), F-09 (manifiesto con conteos del nodo vivo) | **Pendientes**, no bloqueantes según la auditoría. |
| F-08 (identidad de imagen documental) | Documento corregido; ver la nota de la imagen en `REMEDIATION_REPORT.md` §8. |
| Windows, Linux, `setup.ps1` | No probados. |
| Reincorporación a la replicación | No demostrada (Integrante 2). |
