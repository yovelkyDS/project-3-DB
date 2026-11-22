# Validación del desarrollo del integrante 2

Fecha: 22 de noviembre de 2026 (Costa Rica).

La imagen PostgreSQL 17.12 / PostGIS 3.5.4 se construyó en este equipo, se iniciaron los seis nodos y se aplicaron las migraciones y los datos sintéticos existentes del integrante 1 (41 objetos por campus). No se reutilizan los resultados de auditorías antiguas como evidencia de esta extensión.

| Comprobación | Resultado | Evidencia |
|---|---|---|
| Compilación de los tres módulos Python | Correcta | `python -m py_compile` |
| Pruebas locales del coordinador | 6 correctas | `evidence/distributed/unit.log` |
| Instalación de los dos niveles, consolidación y vistas | Correcta; comparación completa sin diferencias | `evidence/distributed/setup.log` |
| Regresión SQL de infraestructura, modelo e identificadores de I1 | 392 PASS, 0 FAIL | `evidence/distributed/base_sql.log` |
| CRUD, permisos y propagación en las ocho capas y cinco campus | Correcto; 120 etapas de propagación registradas (40 casos de inserción, modificación y borrado), sin errores de permisos | `evidence/distributed/integration.log` |
| PITR real y migración de recovery | A presente, B ausente y registro de ids correcto | `evidence/distributed/pitr_verify.log`, `recovery_migrate.log` |
| Reincorporación de San Carlos | Correcta; comparación completa en ambas rutas, sin diferencias | `evidence/distributed/rejoin.log` |
| Nuevas ediciones y 2PC desde el reemplazo | Correctas las ocho capas; 24 etapas de propagación y los tres escenarios 2PC | `evidence/distributed/post_rejoin.log` |
| Autenticación central, carga y dibujo desde QGIS | Pendiente de I3 | No se ha instalado ni validado el complemento en esta sesión |
| Distribución real de estilos | Pendiente de la tabla de estilos de I3 | Comando `styles` implementado, todavía sin validación visual |

Las seis pruebas locales cubren confirmación, reversión, interrupción antes de decidir, interrupción tras decidir, confirmación parcial con reintento y ranuras únicas por destino. La regresión SQL fue concurrente con la integración y puede observar un objeto temporal adicional; conserva cero ids duplicados y cero fallos.

## Detalle de recuperación

Respaldo: `/backups/physical/san_carlos/20261122T184838Z/data`, verificado con pg_verifybackup. Objetivo PITR: `2026-11-22 18:48:50.176612+00`. A: `3000000060`; B: `3000000061`. La restauración pasó a la línea de tiempo 2. La reconciliación retiró B de las copias y recuperó el atributo anterior de A.

Git Bash convirtió inicialmente `/backups` en una ruta de Windows y la recuperación no arrancó. Se corrigió `scripts/recovery/pitr_demo.sh` para excluir `RECOVERY_BASEBACKUP` de esa conversión; la sintaxis de Bash y una prueba con ruta ficticia se comprobaron. El guion que estaba ejecutándose se interrumpió al actualizar su archivo. Se conservó el respaldo y se recreó solamente el contenedor recovery con el directorio `data` correcto, sin borrar volúmenes. Se completaron separadamente las verificaciones PITR y las migraciones, con código 0. Por ello `pitr_console.log` es un registro parcial, y la evidencia del resultado está en `pitr_verify.log`, `recovery_migrate.log` y `rejoin.log`.

Estado del laboratorio después de reincorporar: `pg-san-carlos` detenido, `pg-recovery` como dueño de San Carlos en **55436**, central y otros cuatro campus activos. No iniciar el dueño anterior mientras se use el reemplazo. El mapeo administrativo está en `.distributed-state/routes.json`; los datos anteriores siguen en el volumen original.

