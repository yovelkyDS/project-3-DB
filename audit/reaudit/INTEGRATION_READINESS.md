# Preparación para I2/I3 — segunda auditoría

**Los seis nodos activos permiten comenzar la integración. La entrega definitiva permanece bloqueada por RA-01 en la recuperación antigua.**

## Compatibilidad comprobada

Las tablas conservan nombres `local_<campus>.<capa>`, columnas, PK bigint, campus_id, geometría/SRID 5367 y replica identity. La comparación de firmas de los cinco orígenes originales y de los cinco del laboratorio fue positiva. La plantilla central de 40 destinos volvió a pasar la comparación completa de la suite. Una publicación reversible de San José incluyó exactamente ocho tablas; `ops` quedó fuera.

No se cambiaron Compose ni los parámetros de replicación. `wal_level=logical`, slots 16 y los parámetros ya declarados habilitan el trabajo de I2. `max_prepared_transactions=0` sigue vigente; coordinar su elevación solo si I2 elige 2PC. No hace falta rediseñar la arquitectura para integrar.

El nuevo registro es local por campus; no añade columnas publicadas. Los destinos centrales conservan la plantilla sin triggers de asignación y sin secuencia. Las copias de otros campus deben permanecer separadas de los originales. No replicar `ops` ni aplicar hacia tablas originales sin el mecanismo correcto de registro.

## Contrato de seguridad

I2 debe hacer que sus vistas y triggers de edición inserten sin id o con NULL en el original propietario y reciban `RETURNING id`. Las funciones de edición que implemente deben validar identidad/campus; no confiar en el GUC. Si usa SECURITY DEFINER, debe revisar qué identidad evalúan sus funciones y evitar aceptar un ID proporcionado por el cliente bajo privilegios del propietario. La autorización de mantenimiento se reserva a operadores, no a cuentas QGIS.

La auditoría ejecutó INSERT automático y ataques de ID explícito con un editor de laboratorio sin privilegio de secuencia. El primero funcionó y los ataques fallaron. No existen todavía las vistas, cuentas finales ni auth de I2/I3; sus futuros permisos y la edición ajena se deberán probar cuando existan. No se aprueban esos módulos por adelantado.

I3 puede conservar el contrato de conexión/base/SRID/id bigint; no se necesita modificarlo por 0103. Sus roles y auth, complemento, estilos y pruebas de QGIS siguen siendo su responsabilidad. Usar sslmode=require en los clientes; el servidor actual todavía permite TCP sin TLS (F-06).

## Nodo recuperado que se entrega

El `sigtec-pg-recovery-1` conservado es una demostración anterior a 0103. No debe habilitarse como nuevo origen de escritura con la afirmación de que F-02 está corregido allí. En su copia aislada se confirmó el duplicado de dos capas.

La recomendación actual de `make migrate` no actualiza ese servicio. El comando con NODE=recovery también termina 0 sin migrar. La plantilla de secuencia consulta el registro ausente y requiere antes la actualización real. I1 debe entregar la ruta comprobada descrita en RA-01, o identificar otra recuperación conforme para la entrega y preservar la histórica. Esto actualiza el modelo de I1; no implementa la reincorporación de I2.

El PITR nuevo de esta auditoría sí recuperó un origen migrado: A anterior/B fuera, registro coherente y marca RECUPERADA. Su contenedor `sigtec_reaudit_pitr` quedó **detenido**, con `sigtec_reaudit_20261120_pgdata` y `sigtec_reaudit_20261120_wal` conservados. Es evidencia de prueba, no una sustitución silenciosa del nodo de entrega documentado.

## Trabajo posterior de I2, sin atribuirlo a I1

I2 deberá decidir cuál será el único origen activo del campus, reconciliar filas posteriores al objetivo que ya estén en el central y verificar ambas rutas de replicación. Debe inspeccionar publicaciones, suscripciones y slots existentes al restaurar; no recrear a ciegas objetos que ya estén en el catálogo. Antes de arrancar una copia física futura con suscripciones configuradas, aislar sus conexiones de salida. Ajustar la secuencia por máximos confiables no reconcilia por sí solo actualizaciones o bajas.

La recuperación nueva se probó sin suscripciones presentes. No se implementó ni certificó la reincorporación distribuida, el retorno central→campus ni una sesión QGIS sobre el sistema recuperado. La falta de esos módulos no se usa como motivo de rechazo de I1.

Evidencia: `raw/integration_catalogs.json`, `integration_independent.json`, `full_suite_console.log`, `legacy_recovery_reproduction.json`, `make_migrate_recovery.log`, `pitr_parameters.json`.
