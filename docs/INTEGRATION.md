# Integración con los Integrantes 2 y 3

Este documento es la interfaz entre la infraestructura del Integrante 1 y el trabajo de los
demás integrantes. Todo lo que aparece aquí como "implementado" fue ejecutado y verificado;
lo marcado como "pendiente" **no** lo implementa el Integrante 1.

## 1. Lo que ya existe y se puede usar

| Recurso | Valor |
|---|---|
| Base de datos | `sigtec` en los seis nodos |
| Red Docker | `sigtec_net`; cada nodo en el puerto interno **5432** |
| Superusuario | `postgres`, contraseña `POSTGRES_PASSWORD` en `.env` (solo administración) |
| Rol de respaldo | `sigtec_backup` (`LOGIN REPLICATION`, `pg_read_all_data`). No usarlo para replicación lógica |
| Autenticación | SCRAM-SHA-256; TLS activo (certificado autofirmado). `pg_hba.conf`: conexiones físicas de replicación solo para `sigtec_backup`; conexiones normales (incluida la replicación **lógica**, que usa una conexión normal a la base) para cualquier rol con contraseña |
| Esquemas | `local_<campus>` (ocho capas, en su campus) · `ops` (metadatos, en todos) |
| Esquemas reservados, sin crear | `global`, `qgis` (Integrante 2), `auth` (Integrante 3) |

| Nodo | Servicio / host interno | Puerto host | `campus_id` | Esquema original |
|---|---|---|---|---|
| Central | `pg-central` | 55430 | — | — |
| Cartago | `pg-cartago` | 55431 | 1 | `local_cartago` |
| San José | `pg-san-jose` | 55432 | 2 | `local_san_jose` |
| San Carlos | `pg-san-carlos` | 55433 | 3 | `local_san_carlos` |
| Alajuela | `pg-alajuela` | 55434 | 4 | `local_alajuela` |
| Limón | `pg-limon` | 55435 | 5 | `local_limon` |
| Recuperación (aislada) | `pg-recovery` | 55436 | la del nodo restaurado | — |

Desde un contenedor de la red: `host=pg-san-carlos port=5432 dbname=sigtec`.
Desde el host (QGIS, psql): `host=127.0.0.1 port=55433 dbname=sigtec sslmode=require`.
Para abrir los puertos a otra máquina: `SIGTEC_BIND_ADDRESS=0.0.0.0` en `.env` y `make up`
(hágalo solo en una red de confianza).

## 2. Integrante 2 — replicación, `global`, `qgis`, transacción distribuida

### 2.1 Parámetros ya configurados (los seis nodos)

| Parámetro | Valor |
|---|---|
| `wal_level` | `logical` |
| `max_wal_senders` / `max_replication_slots` | 16 / 16 |
| `max_logical_replication_workers` / `max_worker_processes` | 8 / 16 |
| `max_slot_wal_keep_size` | 4GB (una ranura abandonada no llena el disco) |
| `track_commit_timestamp` | `on` (útil para auditar conflictos) |
| `cluster_name` | `pg-central`, `pg-cartago`, … |

No se crearon publicaciones, suscripciones ni ranuras.

### 2.2 Estructura de las tablas originales

Ocho tablas por campus: `edificios`, `carreteras`, `aceras`, `parqueos`, `zonas_verdes`,
`puntos_interes`, `iluminacion`, `accesibilidad` (columnas en
[DATA_DICTIONARY.md](DATA_DICTIONARY.md)). Todas tienen PK `id bigint`, `campus_id smallint`,
`geom geometry(<tipo>,5367)` y `REPLICA IDENTITY DEFAULT` (la PK), suficiente para publicar
`INSERT`, `UPDATE` y `DELETE`.

### 2.3 Reglas de identificadores que la replicación debe respetar

* `id = campus_id × 10⁹ + consecutivo`; lo asigna el disparador `BEFORE INSERT` del campus con
  su secuencia `local_<campus>.objeto_id_seq` (compartida por las 8 capas).
* Un `INSERT` con `id` explícito en un esquema **original** se rechaza (`23514`). Las vistas
  `INSTEAD OF` deben insertar **sin** `id` (u `id = NULL`) en el nodo del campus propietario y,
  si lo necesitan, leer el id asignado con `RETURNING id`.
* `id` y `campus_id` son inmutables (`UPDATE` rechazado, `23514`).
* **Unicidad entre capas** (migración `0103`): cada id confirmado queda en
  `ops.identificadores_globales` (`PRIMARY KEY (id)`), alimentado por el disparador
  `AFTER INSERT trg_30_registrar_identificador` de las ocho tablas. Dos sesiones concurrentes con
  el mismo id en capas distintas: la segunda espera y recibe `23505`. Los ids de objetos
  eliminados permanecen registrados y **no se reutilizan**.
* Modo mantenimiento (solo para reparar o reincorporar datos, no para la replicación normal):
  requiere `SET sigtec.permitir_id_explicito = on` **y** ser miembro del rol `NOLOGIN`
  `sigtec_mantenimiento_id`; el id debe haber sido emitido por la secuencia y no estar en el
  registro. Sin el rol: `42501`. El GUC por sí solo ya no autoriza nada. Para conceder:
  `GRANT sigtec_mantenimiento_id TO <operador>`.
* Un esquema original tiene **24 disparadores** (3 por capa: asignación de id, inmutabilidad,
  registro). `make verify` lo comprueba y ejecuta `sql/checks/verificar_registro_ids.sql`.
* **Los disparadores no afectan al apply de la replicación lógica** en los destinos, porque las
  tablas destino del central no tienen disparadores ni secuencia (ver 2.4); y los disparadores
  normales no se ejecutan en el apply salvo que se marquen `ENABLE REPLICA/ALWAYS`.
* Por esa misma razón, el registro **no se alimenta** con filas aplicadas en modo
  `session_replication_role = replica` ni cuando un superusuario deshabilita disparadores. No
  replique **hacia** los esquemas originales de un campus; si alguna vez fuera necesario
  escribir en ellos por otro camino, ejecute luego `sql/checks/verificar_registro_ids.sql`.
* `ops.identificadores_globales` es local de cada campus (está en `ops`, que no se publica) y
  las tablas destino del central (2.4) no la usan.
* La imagen actual habilita `max_prepared_transactions = 16` para el coordinador de I2.
  Si se utiliza una imagen anterior, reconstruirla y recrear los contenedores; ver INTEGRANTE_2.md.

### 2.4 Tablas destino en el central (plantilla)

[`sql/templates/central_copias_locales.sql`](../sql/templates/central_copias_locales.sql) crea en
el central los cinco esquemas `local_<campus>` con **exactamente** la misma definición de las
ocho tablas (incluye la misma fuente `sql/schema/capas_locales.sql`), sin secuencia ni
disparadores, conservando PK, `CHECK` y GiST. No se aplica automáticamente; la prueba
`global.plantilla_central_compatible` la aplica en un clúster temporal y compara firmas columna
por columna con los cinco campus (resultado: compatible). Para aplicarla:

```bash
docker compose --profile tools run --rm -T sigtec-tools -c '. scripts/lib/db.sh
  psql_su central -v ON_ERROR_STOP=1 -f sql/templates/central_copias_locales.sql'
```

### 2.5 Recomendaciones para publicaciones y suscripciones

* Publicar solo las ocho tablas del esquema local (`CREATE PUBLICATION … FOR TABLES IN SCHEMA
  local_<campus>` o la lista explícita). **No publicar `ops`**: es información propia de cada
  nodo (`ops.node_info` es distinta en cada uno y las migraciones son locales).
* Crear un rol de replicación propio con contraseña generada (por ejemplo, agregar
  `SIGTEC_REPL_PASSWORD=__GENERAR__` a `.env.example`; `scripts/setup.sh` genera cualquier
  variable con ese marcador) en lugar de reutilizar `postgres` o `sigtec_backup`.
* La conexión de la suscripción usa los nombres internos (`host=pg-cartago port=5432
  dbname=sigtec`) y puede exigir `sslmode=require`.
* `make backup-logical` restaura con `--no-subscriptions`, de modo que una restauración no
  reactiva suscripciones por accidente.

### 2.6 Después de un PITR (reincorporación — **no demostrada**)

* **Requisito previo de I1 (RA-01):** la instancia recuperada que se entrega debe estar al día:
  `make migrate NODE=recovery` y `make recovery-status` con "apta para entregar" (código 0).
  Una copia anterior a `0103` sin migrar admite ids repetidos entre capas y no debe recibir
  escrituras ni reincorporarse. Procedimiento:
  [remediation/RA-01/RECOVERY_MIGRATION_GUIDE.md](../remediation/RA-01/RECOVERY_MIGRATION_GUIDE.md).

* `pg_basebackup` no incluye ranuras de replicación y la instancia recuperada cambia de línea de
  tiempo: hay que recrear la publicación/ranura en el nodo recuperado y la suscripción en el
  central (con `copy_data` según la estrategia elegida).
* Los objetos posteriores al instante objetivo (en la demostración, el cambio B) pueden seguir en
  las copias del central; el Integrante 2 debe decidir si se eliminan o se reconcilian.
* Antes de aceptar escrituras en el nodo recuperado, ajustar su secuencia por encima del máximo
  id que el central conozca de ese campus (la plantilla también considera el registro de
  identificadores); reincorporar un objeto con su id original requiere un miembro de
  `sigtec_mantenimiento_id`:
  [`sql/templates/ajustar_secuencia_tras_recuperacion.sql`](../sql/templates/ajustar_secuencia_tras_recuperacion.sql)
  (probado en `pg-recovery`, ver [BACKUP_RECOVERY.md](BACKUP_RECOVERY.md)).
* La instancia recuperada de la demostración se inspecciona con `make psql NODE=recovery`
  (o `127.0.0.1:55436`), sin afectar el nodo original.

## 3. Integrante 3 — autenticación, cuentas, complemento PyQGIS

| Dato | Valor |
|---|---|
| Nodo de autenticación | central, `127.0.0.1:55430`, base `sigtec` |
| Nodo de datos por usuario | el de su campus (55431–55435), base `sigtec` |
| `campus_id` | 1 Cartago · 2 San José · 3 San Carlos · 4 Alajuela · 5 Limón |
| SRID de todas las capas | EPSG:5367 (el complemento no necesita reproyectar) |
| Capas a cargar | ocho vistas `qgis.v_*` del nodo del campus (Integrante 2), cargadas por el complemento SIG-TEC |
| Llave primaria para QGIS | `id` (bigint) |
| Altas desde QGIS | sin `id` (lo asigna PostgreSQL). Las cuentas de edición **no** deben ser miembros de `sigtec_mantenimiento_id`; un id explícito se rechaza con `23514`/`42501` |
| Contraseñas de las cuentas de prueba | `SIGTEC_QGIS_CARTAGO_PASSWORD` … `SIGTEC_QGIS_LIMON_PASSWORD` en `.env`, generadas por el instalador y sincronizadas por `make integrante3-setup` |
| TLS | activo; `sslmode=require` (certificado autofirmado, por eso no `verify-full`) |

Para leer una contraseña generada sin mostrar las demás:

```bash
grep '^SIGTEC_QGIS_SAN_CARLOS_PASSWORD=' .env | cut -d= -f2-
```

Instalación y pruebas del complemento: [INTEGRANTE_3.md](INTEGRANTE_3.md). No se debe conectar QGIS como `postgres`; las cuentas finales solo tienen DML sobre las vistas de su campus.

## 4. Responsabilidades integradas

| Elemento | Responsable |
|---|---|
| Publicaciones, suscripciones, esquema `global` y su consolidación | Integrante 2 |
| Vistas `qgis.v_*`, disparadores `INSTEAD OF`, transacción distribuida | Integrante 2 |
| Reincorporación del nodo recuperado a la replicación | Integrante 2 |
| Esquema `auth`, cuentas `qgis_*`, roles y permisos de usuarios finales | Integrante 3 |
| Complemento PyQGIS, estilos (`layer_styles`), manual de usuario | Integrante 3 |

## Extensión del integrante 2

La implementación nueva y el contrato actualizado de vistas, permisos, cuentas de datos,
replicación y reincorporación se documentan en [INTEGRANTE_2.md](INTEGRANTE_2.md).
La sección anterior conserva el estado de entrega original del integrante 1.

## Extensión del integrante 3

El esquema `auth`, la función segura basada en `session_user`, las cuentas centrales, los estilos y el complemento se instalan con `make integrante3-setup`. El manual, tratamiento de errores, pruebas y guion visual están en [INTEGRANTE_3.md](INTEGRANTE_3.md).
