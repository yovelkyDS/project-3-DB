# Segunda auditoría técnica independiente — SIG-TEC, Integrante 1

**Veredicto: NO APROBADO.** Fecha: 20 de noviembre de 2026; America/Costa_Rica (UTC−06). Auditor: Codex. Alcance: remediación y entrega de infraestructura de I1; no implementación de I2/I3.

**¿Puede el Integrante 1 cerrar definitivamente su responsabilidad y entregar la infraestructura al Integrante 2 sin defectos bloqueantes conocidos? No.** F-01 está corregido y F-02 está corregido en los cinco campus activos, pero el nodo recuperado original entregable conserva F-02. La ruta de actualización indicada para ese caso no lo migra y devuelve éxito. Este hallazgo se identifica como **RA-01, ALTO**, continuación de F-02 en la recuperación anterior a 0103. No se rechaza la migración 0103 ni el PITR nuevo: ambos funcionaron en los ámbitos probados.

El bloqueo tiene alcance concreto: entregar también el nodo recuperado como infraestructura segura para reincorporar. I2 puede comenzar sus módulos sobre los seis nodos activos. La auditoría no exige a I1 implementar publicaciones, suscripciones, vistas, autenticación, QGIS ni reconciliación distribuida.

## Corrección indispensable para desbloquear

Entregar un procedimiento **ejecutable y probado** que actualice una recuperación anterior a 0103, dirigido expresamente a `pg-recovery`, conservando la identidad del campus restaurado y sus datos. Debe aplicar y registrar 0103, comprobar los 24 triggers, la coherencia del registro y el ajuste de secuencia, y devolver error ante un destino inválido o una migración fallida. Actualizar la guía para que identifique ese procedimiento y comprobar en una copia anterior a 0103 que el editor ya no pueda repetir F-02. Puede entregarse una recuperación nueva conforme a 0103, preservando la anterior como histórica, si se identifica inequívocamente cuál recibe I2 y se valida la transición desde respaldos antiguos. No se requiere eliminar el volumen existente.

No se elevan F-06, F-07 ni F-09 a bloqueantes de esta entrega académica. Sus correcciones están separadas en [FINDINGS.md](FINDINGS.md).

## Método y procedencia

Se comenzó con diferencias entre `audit/lab/`, instantánea conservada de la primera auditoría, y las fuentes actuales. No hay `.git`; no se inventó un commit ni un historial. Después se leyeron los cinco informes originales, la referencia de distribución y la documentación de remediación: `READY_FOR_REAUDIT`, `REMEDIATION_REPORT`, `GLOBAL_ID_FIX`, `BACKUP_FIX`, `REGRESSION_TESTS`, `INTEGRATION_IMPACT`, notas de imagen/rutas y evidencia PITR. Se inspeccionaron scripts y pruebas antes de ejecutarlos.

Se distinguen **código inspeccionado**, **evidencia anterior de remediación** y **ejecución de esta auditoría**. Las corridas anteriores atribuidas a Claude no se cuentan como propias. Esta auditoría volvió a ejecutar la suite existente y añadió instrumentos propios en `probes/`. Reejecutar una prueba escrita por la remediación es evidencia de ejecución propia, sin atribuirse su autoría.

Se usó `sigtec_remed`, puertos 57430–57436. Los originales se consultaron sin escrituras de aplicación. Sus respaldos/WAL solo se montaron en lectura y se copiaron a almacenamiento efímero para restaurar. Para PITR se conservaron la recuperación existente y sus volúmenes: se detuvo temporalmente solo la recuperación del laboratorio, se crearon dos volúmenes nuevos y se usó temporalmente 57436 con otro contenedor. Se reiniciaron los servicios del laboratorio al terminar. No se usaron `clean.sh`, `down -v`, `--reset` ni retención destructiva.

## Diferencias efectivas y 0103

[source_diff.patch](raw/source_diff.patch) y [source_changes.json](raw/source_changes.json) registran 20 archivos de código/Makefile distintos o nuevos. `scripts/`, `sql/`, `tests/` y `docker/` de la raíz y del laboratorio coincidían byte por byte al inicio. Las migraciones 0001/0002/0101/0102, el esquema geográfico, la semilla, Compose, Dockerfile y la configuración PostgreSQL no cambiaron frente a la instantánea original en esos directorios. La documentación también fue revisada; el diff adjunto se concentra en código y Makefile.

0103 agrega `ops.identificadores_globales(id PRIMARY KEY)`, precarga las filas existentes y rechaza duplicados previos. La aplicación real usa `--single-transaction`. El trigger `AFTER INSERT` reserva el ID en la misma transacción; el índice único arbitra la concurrencia entre tablas. La asignación pasa a `SECURITY INVOKER`; el GUC debe acompañarse de pertenencia efectiva a `sigtec_mantenimiento_id`. La función de autorización solo permite EXECUTE a mantenimiento; las funciones DEFINER usan `search_path=pg_catalog, pg_temp`. PUBLIC no puede escribir en el registro, crear en el esquema original ni ejecutar el trigger de registro.

Se corroboraron esos catálogos en los cinco originales y se ejecutaron los ataques de permisos en el laboratorio. Los originales tienen **207 objetos, 207 IDs distintos, cero objetos sin registro y cero prefijos incorrectos**, distribuidos 41/41/43/41/41. Cada campus activo tiene 24 triggers habilitados. La suite ejecutó además la actualización desde 0102 con duplicados: aborto sin instalación parcial; tras resolver el conflicto, aplicación e idempotencia correctas. No se certifica una migración en caliente con escritores simultáneos; la actualización debe coordinarse antes de abrir escrituras.

## F-01: antes y después comprobados

Esta auditoría ejecutó los scripts originales conservados, con contraseña incorrecta y destinos `/tmp`: ambos devolvieron **0**, publicaron un directorio y anunciaron OK sin copia válida. Evidencia: [F01_original_baseline.json](raw/F01_original_baseline.json).

Con el código remediado, la misma clase de prueba devolvió **1**, cero publicados y ERROR en ambos tipos: [f01_independent.json](raw/f01_independent.json). La solución utiliza comprobaciones de comandos, `run_step`, directorios ocultos en curso/fallidos y publicación mediante rename tras validación. Se leen íntegramente los bloques del dump; se verifica estructura y `pg_verifybackup` para la copia física.

La suite negativa/positiva terminó 36/36, incluyendo autenticación en seis nodos, servidor inaccesible, almacenamiento no escribible, escritura parcial, dump truncado y copia física alterada. Las rutas públicas `make backup-logical`, `backup-physical` y `backup` devolvieron **2** ante el fallo y no continuaron a la etapa dependiente; tras resincronizar únicamente el rol del central del laboratorio volvieron a funcionar: 10/10. La existencia de un archivo no se consideró prueba suficiente de restauración.

Se restauraron independientemente las **seis copias lógicas y seis físicas originales más recientes**, con la imagen actual, en un contenedor sin red y con los orígenes `:ro`. Las seis físicas pasaron además `pg_verifybackup`. Todas restauraron/arrancaron, con PostGIS, identidad, capas y registro coherentes. Evidencia: [original_restores.log](raw/original_restores.log). F-01 queda cerrado en los escenarios comprobados.

## F-02: resultado positivo en campus y excepción bloqueante

El instrumento propio creó un editor sin USAGE sobre la secuencia. El INSERT automático funcionó; el INSERT explícito con GUC, la función de autorización, la escritura del registro, deshabilitar triggers, el modo réplica y autoasignarse mantenimiento fueron rechazados con `42501`.

En dos conexiones autorizadas se reservó **1000000067** en capas distintas: la segunda esperó **3,84 s**, recibió `23505` y quedó una sola fila confirmada. Con **1000000068**, al revertir la primera transacción, la segunda esperó **3,85 s** y confirmó; el registro identificó la capa correcta. Se verificaron seis PID independientes superpuestos y **180 inserciones automáticas** adicionales; los 224 objetos de Cartago existentes al finalizar esa prueba tenían 224 IDs distintos y cero faltantes de registro. La suite añadió ocho conexiones sobre ocho capas en cada campus, rollback, eliminación sin reutilización, reinicio y restauración. Evidencia: [ids_independent.json](raw/ids_independent.json).

Sin embargo, `sigtec-pg-recovery-1` conserva solo 0101/0102. La guía de remediación indica `make migrate` antes de aceptar escrituras, pero `all` solo incluye los seis nodos activos y `recovery` no es un nodo admitido por el migrador. **`make migrate NODE=recovery` devuelve 0 después de imprimir `nodo inválido: recovery`.** No aplica 0103. El error de `nodes_expand` se pierde dentro del `for node in $(...)`.

Se exportó ese nodo con `pg_dump` sin cambiarlo y se restauró la copia con sus ACL en un contenedor sin red. Un editor sin permiso de secuencia confirmó **3000000083 en dos capas**, desde dos conexiones: ambas devolvieron 0, dos filas confirmadas. Evidencia: [legacy_recovery_reproduction.json](raw/legacy_recovery_reproduction.json), [make_migrate_recovery.log](raw/make_migrate_recovery.log). La plantilla de ajuste ahora consulta el registro ausente, de modo que ajustar la secuencia tampoco sustituye a migrar. Es RA-01, no corrupción del original por esta auditoría.

## PITR y F-03/F-04/F-05

La evidencia previa `20261120T212428Z` se contrastó con consultas y logs del contenedor existente. Después se repitió PITR en una instancia nueva, desde respaldo nuevo de San Carlos del laboratorio, tras dos cambios y SIGKILL solo a ese origen temporal:

| Dato | Nueva ejecución propia, UTC |
|---|---|
| Corrida | `reaudit_20261120T214840Z` |
| A | ID 3000000095; commit 21:48:42.179164 |
| Objetivo | 21:48:43.511729 |
| B | ID 3000000096; commit 21:48:44.859247 |
| WAL archivado | `000000010000000000000014` |
| Recuperación | A con descripción anterior; B ausente; timeline 2; 44 objetos/44 IDs/0 sin registro |
| Origen de laboratorio | A modificado por B y B presente tras reiniciar |

Se verificó `A < objetivo < B` en SQL y el log detuvo la reproducción antes del commit de B. El script real `marcar-recuperada` terminó correctamente y almacenó exactamente una marca RECUPERADA. El pipeline `t()` extraído sin cambios preservó un fallo inyectado 37. Se validan los componentes corregidos de F-03; no se afirma haber ejecutado sin modificaciones el orquestador completo `pitr_demo.sh`, que exige borrar la recuperación existente para otra corrida. El arnés independiente permitió preservar ese volumen.

F-04 leyó 57430–57436 desde `.env` sin exportarlos y detectó esos puertos ocupados al consultar un nombre de proyecto vacío. El primer arranque desde `.env.example` se inspeccionó estáticamente, sin recrear seis volúmenes. F-05 ejecutó `APPLY=0` en el laboratorio y confirmó simulación; valores inválidos fallaron antes de la retención; `APPLY=1` solo se inspeccionó con `make -n`.

## Las 733 pruebas y su límite

La ejecución propia de `run_tests.sh --full` terminó **0**, con **733 PASS y 0 FAIL**: 392 SQL, 36 respaldo, 272 identificadores y 33 infraestructura/higiene/idempotencia/persistencia. La cuenta se volvió a calcular del log. Son aserciones, varias repetidas por campus/entorno; hay 15 etiquetas repetidas entre suites, no 733 casos conceptualmente distintos.

Las 292 aserciones SQL anteriores permanecen; sus fuentes 10–30 no se debilitaron. La exclusión nueva de `audit/` afecta la búsqueda de rutas absolutas en evidencia externa, no elimina pruebas SQL, permisos, concurrencia ni la búsqueda de secretos. La auditoría hizo adicionalmente su propio escaneo: ningún secreto original apareció fuera de `.env`.

La cobertura es suficiente para confirmar las reparaciones en instalaciones actuales, **insuficiente para aprobar la transición del nodo recuperado antiguo**. No prueba que `migrate recovery` falle correctamente ni actualiza una recuperación pre-0103. También faltaba la carrera de metadatos de respaldo F-09, reproducida aquí. La comprobación de idempotencia compara conteos/suma de IDs y puede perder el fallo del primer comando de su `&&`; no equivale a verificar todo el contenido. La prueba de etiquetas solo busca `latest`, por lo que no prueba inmutabilidad de la imagen local. Estas limitaciones explican por qué el total verde no libera RA-01.

## Imagen y reproducibilidad

Los originales siguen ejecutando `sha256:cc0beda012c0d724bfb69afb0734bc5ac872a5d38db73417305b49dca17402af`; las etiquetas `sigtec/postgis` y `sigtec-remed/postgis` apuntan a `sha256:fd04b3df6c21a4f2d7c34afb2f8280bacf0035dd031c754eb1caae90e1ed455c`. Recrear un original con su configuración actual seleccionaría la segunda construcción; reiniciarlo conserva la primera. Se verificó igualdad del binario PostgreSQL y diferencia de `postgis-3.so`; versiones efectivas PG 17.12/PostGIS 3.5.4/GEOS 3.15.0/PROJ 9.9.0 y paquetes consultados coinciden.

La restauración de los respaldos originales con la imagen actual demuestra compatibilidad práctica de recuperación en este host. No demuestra identidad binaria ni una reconstrucción futura idéntica: `apt-get` no fija todas las dependencias y una etiqueta local se puede reasignar. La separación actual de etiquetas para el laboratorio es apropiada. No se recompiló sin caché en esta segunda auditoría; la corrida anterior se trata como evidencia histórica. F-08 documental está atendido, con observación de reproducibilidad.

## Integración, pendientes y preservación

Las firmas de columnas/tipos/NOT NULL coincidieron entre los cinco campus originales y entre los cinco del laboratorio; la plantilla central pasó nuevamente la comparación de la suite. Una publicación reversible en San José incluyó ocho tablas y excluyó `ops`. PK/REPLICA IDENTITY, SRID y parámetros habilitantes continúan compatibles con el contrato. I2/I3 pueden trabajar conservando la arquitectura, insertando sin ID desde las vistas y reservando mantenimiento a operadores. El rechazo por permisos se probó con roles de laboratorio; no se certifican cuentas/vistas finales todavía inexistentes.

F-06 queda BAJO: conexión TCP sin TLS aceptada. F-07 queda BAJO: PowerShell no incorpora claves nuevas de `.env.example` en un `.env` existente; Windows no se ejecutó. F-09 queda MEDIO: se obtuvo un dump válido, luego se confirmó una fila desde otra conexión durante una pausa controlada del respaldo y el manifiesto tomó el estado posterior. El restore devolvió 1 por conteos 99 frente a 98 y secuencia 249 frente a 248, aunque `pg_restore` terminó y el registro era coherente. Es un falso negativo de verificación, no una copia corrupta ni reaparición de F-01.

[final_integrity.json](raw/final_integrity.json) confirma 322 archivos preexistentes sin cambios, ningún volumen preexistente desaparecido y snapshots SQL originales idénticos en los siete servicios, incluidos hashes de contenido geográfico. Los seis originales y su recuperación, y los siete servicios de `sigtec_remed`, terminaron healthy. La recuperación nueva `sigtec_reaudit_pitr` quedó detenida, con sus volúmenes conservados. Se dejaron filas de prueba solo en el laboratorio. No se aplicaron correcciones al proyecto.

Detalle: [matriz](COMPLIANCE_MATRIX.md), [pruebas](TEST_RESULTS.md), [hallazgos](FINDINGS.md), [integración](INTEGRATION_READINESS.md), [veredicto](FINAL_VERDICT.md).
