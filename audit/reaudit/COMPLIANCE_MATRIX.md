# Matriz de cumplimiento — segunda auditoría

20 noviembre 2026. APROBADO se limita al escenario con evidencia directa. ESTÁTICO o NO VERIFICADO no equivale a aprobación funcional.

| Objetivo / requisito | Evidencia directa de esta auditoría | Estado | Observación |
|---|---|---|---|
| Comparar código original y remediado | `raw/source_diff.patch`, `source_changes.json`, equivalencia raíz/lab | VERIFICADO | 20 archivos código/Makefile; sin historial Git disponible |
| Reproducir F-01 original | `F01_original_baseline.json` | REPRODUCIDO EN BASELINE | Ambos rc=0/OK con contraseña errónea y copia inválida |
| F-01 remediado | `f01_independent.json`, suite 36/36, `host_backup_paths.log` | APROBADO | Scripts rc=1; make rc=2; ningún respaldo negativo publicado |
| Respaldos positivos nuevos | Suite ejecutada: 6 lógicos y 6 físicos con restauración | APROBADO | No solo TOC/manifest |
| Respaldos originales con imagen actual | `original_restores.log` | APROBADO | 6/6 lógicos restaurados y 6/6 físicos arrancados; montajes origen RO, sin red |
| 0103 y privilegios actuales | `integration_catalogs.json`, fuente y suite | APROBADO EN CAMPUS ACTIVOS | PK de registro, INVOKER/DEFINER, ACL, 24 triggers por campus |
| Aborto de 0103 ante duplicados | Suite `actualizacion.*` ejecutada | APROBADO | Clúster temporal desde 0102, datos conservados y migración sin instalación parcial |
| ID explícito de editor con GUC | `ids_independent.json` | APROBADO EN CAMPUS MIGRADOS | 42501; automático permitido sin USAGE de secuencia |
| Carrera autorizada entre conexiones | `ids_independent.json` | APROBADO EN CAMPUS MIGRADOS | COMMIT: espera/23505/una fila; ROLLBACK: segunda confirma |
| Concurrencia automática | 6 PID/180 filas propios; suite 8 capas × 5 campus | APROBADO | Sin duplicados ni objetos no registrados |
| IDs actuales en originales | `original_registry_checks.json`, inventarios | APROBADO | 207/207, cero sin registro y cero prefijos incorrectos |
| Protección del nodo recuperado pre-0103 | `legacy_recovery_reproduction.json` | **NO APROBADO** | F-02 reproducido en copia exacta, dos COMMIT/ID duplicado; RA-01 |
| Migrar recuperación antigua siguiendo guía | `migrate_recovery_probe.log`, `make_migrate_recovery.log` | **NO APROBADO** | recovery inválido, rc=0, sin actualizar; all omite recovery |
| Evidencia PITR previa de remediación | Consultas `integration_catalogs.json`, `prior_pitr_container.log` | CORROBORADA | No se cuenta su ejecución como propia |
| PITR nuevo con 0103 | `pitr_parameters.json`, `pitr_new_container.log`, `pitr_independent.json` | APROBADO EN LABORATORIO | A previo/B fuera/timeline2/registro coherente; volúmenes nuevos |
| F-03 marca y propagación | `marker_followup_independent.json`, `F03_pipeline_failure.json` | APROBADO POR COMPONENTES | Marca real almacenada y fallo 37 preservado; arnés corrigió opciones de conexión |
| Orquestador completo pitr_demo sin cambios | Código y evidencia previa | NO REEJECUTADO COMPLETO | Exige reset para recuperación existente; se usó arnés conservador |
| F-04 .env alternativo sin exportar | `residual_independent.json` | APROBADO PARA .env | Detectó 57430–57436; rama sin .env inspeccionada, no desplegada |
| F-05 APPLY=0 / inválido / 1 | `retention_apply0.log`, `residual_independent.json` | APROBADO EN ESCENARIOS SEGUROS | 0 simula, inválido falla, 1 revisado sin ejecutar borrado |
| 733 aserciones reportadas | `full_suite_console.log`, `suite_count.json` | REEJECUCIÓN LEGÍTIMA | 733 PASS/0 FAIL, rc0; no cobertura completa de recuperación antigua/F-09 |
| Exclusiones de suite | Diff y escaneo propio `preservation_files.json` | ACEPTABLE CON LÍMITES | audit excluido solo de rutas absolutas; código funcional sigue incluido |
| F-06 TLS obligatorio | `residual_independent.json` | PENDIENTE, BAJO | disable aceptado; no obligación académica impuesta |
| F-07 actualización PowerShell | Inspección `setup.ps1` | PENDIENTE, BAJO | Windows no ejecutado |
| F-09 manifiesto bajo escritura | `residual_independent.json` | PENDIENTE, MEDIO | Falso rechazo de restore sano reproducido |
| Imagen Docker y recreación | Inventarios/binarios y doce restores con fd04 | COMPATIBILIDAD COMPROBADA CON OBSERVACIÓN | Recrear usa imagen distinta; no reproducibilidad bit a bit |
| Interfaces I2/I3 y arquitectura | Firmas, plantilla central de suite, publicación reversible y privilegios | COMPATIBLES EN NODOS MIGRADOS | La entrega del recuperado antiguo requiere RA-01 |
| Replicación final, QGIS, cuentas y reincorporación | Fuera del alcance implementado | NO CERTIFICADO | Responsabilidad de I2/I3; no se implementó |
| Preservar originales e informes | `final_integrity.json` | APROBADO | 322 archivos intactos, datos originales iguales, volúmenes preservados |
| Instalación completa nueva en host limpio / Linux / Windows | Evidencia histórica y revisión | NO REEJECUTADA / NO VERIFICADO | No se atribuye despliegue de seis volúmenes nuevos a esta segunda auditoría |
