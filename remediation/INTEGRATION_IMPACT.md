# Impacto de la remediación en los Integrantes 2 y 3

Resumen: **no cambia ninguna interfaz que los otros integrantes consuman**. Las ocho tablas, sus
columnas, tipos, PK, `CHECK`, índices GiST, `REPLICA IDENTITY`, SRID, nombres de nodos, puertos,
roles existentes y parámetros de replicación son los mismos. Se agregan un rol, una tabla en
`ops`, tres funciones y un disparador por capa. Detalle normativo en
[docs/INTEGRATION.md](../docs/INTEGRATION.md) §2.3 y §2.6.

## 1. Lo que no cambió (verificado)

| Elemento | Verificación |
|---|---|
| Firmas de las 40 tablas (5 campus × 8 capas) | `global.plantilla_central_compatible` PASS en los originales migrados: la plantilla del central sigue idéntica columna por columna |
| Publicación de las 8 tablas | `test_ids_aislado.sh`: una publicación `FOR TABLES IN SCHEMA local_<campus>` contiene las 8 tablas y **no** `ops`; 48 columnas; replica identity = PK |
| `wal_level`, ranuras, `max_*` | sin cambios en `docker/postgres/conf/` |
| Esquemas `global`, `qgis`, `auth` | siguen sin crearse |
| Inserción sin `id` | sigue funcionando para cualquier rol con `INSERT` (probado con un rol sin privilegio sobre la secuencia) |

## 2. Lo que cambió

| Cambio | Efecto para el Integrante 2 | Efecto para el Integrante 3 |
|---|---|---|
| `ops.identificadores_globales` + `trg_30_registrar_identificador` | Un id confirmado no puede aparecer en otra capa del campus, ni siquiera bajo concurrencia. Al restaurar/reincorporar, la plantilla de ajuste de secuencia considera también el registro. | Ninguno. |
| Id explícito requiere `sigtec_mantenimiento_id` | Las vistas y disparadores `INSTEAD OF` deben insertar **sin** `id` (como ya indicaba el contrato) y leerlo con `RETURNING id`. | Las cuentas de edición de QGIS **no** deben ser miembros de ese rol. |
| 24 disparadores por esquema original (antes 16) | Las restauraciones de prueba los esperan; no afectan al *apply* de la replicación lógica en el central (sus tablas destino no tienen disparadores). | Ninguno. |
| Ids eliminados no se reutilizan | Simplifica la reconciliación: un id nunca designa a dos objetos. | Ninguno. |
| Respaldo fallido → código ≠ 0 y nada publicado | Puede encadenarse en automatizaciones con confianza. | Ninguno. |

## 3. Advertencias para la replicación (Integrante 2)

* No replicar **hacia** los esquemas originales de un campus: el *apply* corre con
  `session_replication_role = replica`, no ejecuta disparadores normales y no alimentaría el
  registro.
* No publicar `ops`.
* `max_prepared_transactions = 0` (valor por defecto, sin cambios): si la transacción distribuida
  usa `PREPARE TRANSACTION`, debe elevarse en la configuración del nodo.
* Reincorporación tras un PITR: el nodo `pg-recovery` original contenía datos anteriores a 0103;
  aplicar `make migrate NODE=recovery` (corrección RA-01: `make migrate` sin `NODE` no incluye la
  instancia recuperada) antes de aceptar escrituras y ajustar la secuencia con
  `sql/templates/ajustar_secuencia_tras_recuperacion.sql`. **La reincorporación no está
  demostrada.**

## 4. Compatibilidad con la futura replicación

* Ninguna columna nueva en las tablas publicadas → las suscripciones no requieren cambios.
* La tabla de registro es local por diseño (cada campus emite sus propios ids con prefijo
  `campus_id × 10⁹`); la unicidad entre campus la sigue garantizando el prefijo.
* `SECURITY DEFINER` solo en funciones con `search_path` fijo; la asignación del id es
  `SECURITY INVOKER`.
* No se introdujeron extensiones, parámetros ni dependencias nuevas.
