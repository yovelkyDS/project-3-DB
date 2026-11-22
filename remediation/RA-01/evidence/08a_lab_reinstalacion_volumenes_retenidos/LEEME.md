# 08a — reinstalación del laboratorio `sigtec_remed` NO limpia (conservada como evidencia)

* `scripts/clean.sh --yes` no pudo eliminar `sigtec_remed_walarchive_san_carlos` ni `sigtec_remed_backups`
  ("Resource is still in use"): los monta el contenedor detenido `sigtec_reaudit_pitr`, creado por la
  segunda auditoría (citado en `audit/reaudit/AUDIT_REPORT.md`; no se modificó ni eliminó). Ver
  `contenedor_reaudit_que_retiene_volumenes.txt`. `clean.sh` informó "Limpieza terminada" y rc 0.
* Consecuencia: el archivo WAL de san_carlos conservaba segmentos de la instalación anterior;
  `sigtec-archive-wal` rechazó (correctamente) sobrescribir `000000010000000000000001`
  ("ya existe con contenido distinto") → `san_carlos.archivado_sin_fallos` FAIL, restauración física
  de san_carlos FAIL, PITR FAIL. Son efectos del volumen retenido, no de RA-01.
* Hallazgo derivado: `pitr_demo.sh` paso 5 ignoraba el fallo de `asegurar-wal` (`| tail -1`) y
  simulaba la falla del nodo sin WAL archivado. Corregido (validación del segmento y del objetivo
  antes del paso 6); ver `08c_guardia_wal/`.
* El script de la tubería se modificó mientras se ejecutaba (error del operador): después de `pitr`
  terminó con un error de sintaxis; no se ejecutaron los pasos posteriores.
* La instalación limpia válida se repitió en un proyecto nuevo `sigtec_ra01`: `08b_lab_instalacion_limpia/`.
