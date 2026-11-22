# Diccionario de datos SIG-TEC

Fuente única de la estructura: [`sql/schema/capas_locales.sql`](../sql/schema/capas_locales.sql).
Las mismas descripciones están en el catálogo (`COMMENT ON`), visibles en QGIS y con `\d+`.

## 1. Convenciones

| Elemento | Convención |
|---|---|
| Base de datos | `sigtec` en los seis nodos |
| Esquemas originales | `local_cartago`, `local_san_jose`, `local_san_carlos`, `local_alajuela`, `local_limon` — uno por campus, en su propio nodo |
| Nombres SQL | minúsculas, sin tildes ni espacios, `snake_case` |
| Geometría | columna `geom`, tipo explícito con SRID: `geometry(Polygon\|LineString\|Point, 5367)` |
| Restricciones | `<tabla>_pkey`, `<tabla>_<campo>_ck`, `<tabla>_<campo>_uk`; índice espacial `<tabla>_geom_gix` (GiST) |
| Unidades | coordenadas, longitudes y anchos en **metros**; áreas en **m²**; potencia en **W** |
| Esquema `ops` | metadatos operativos del Integrante 1 (no se replica) |
| Reservados (no los crea el Integrante 1) | `auth` (I3), `global` (I2), `qgis` (I2) |

## 2. Sistema de referencia

**EPSG:5367 — CR05 / CRTM05** (Costa Rica Transversal de Mercator 2005), proyectado, en metros,
datum CR05. Todas las tablas lo fijan en el tipo de columna; PostGIS rechaza otro SRID
(`22023 Geometry SRID (4326) does not match column SRID (5367)`).

Datos de entrada en longitud/latitud (EPSG:4326): primero se asigna el SRID de origen y luego
se transforma — `ST_MakePoint` recibe **longitud primero**:

```sql
SELECT ST_Transform(ST_SetSRID(ST_MakePoint(-84.510307, 10.362791), 4326), 5367);
-- POINT(444118.34 1145912.93)
```

Los datos de prueba usan exactamente este procedimiento para ubicar cada campus.

## 3. Identificador global

```
id = campus_id × 1 000 000 000 + consecutivo_local        (consecutivo 1 .. 999 999 999)
```

| Regla | Implementación |
|---|---|
| Una secuencia por campus compartida por las 8 capas | `local_<campus>.objeto_id_seq` (`MINVALUE 1 MAXVALUE 999999999 NO CYCLE`) |
| Asignación automática | disparador `trg_10_asignar_identificador` (`BEFORE INSERT`, `SECURITY INVOKER`): si `id` llega NULL u omitido, `id = campus_id·10⁹ + nextval()` mediante `local_<campus>.sigtec_id_siguiente()` (`SECURITY DEFINER`: los editores no necesitan privilegios sobre la secuencia); `campus_id` se completa si falta |
| **Unicidad entre las 8 capas** | registro `ops.identificadores_globales` con `PRIMARY KEY (id)`, alimentado por `trg_30_registrar_identificador` (`AFTER INSERT`) con `INSERT … ON CONFLICT DO NOTHING`: dos transacciones que usan el mismo id en capas distintas no pueden confirmar ambas (la segunda espera y recibe `23505`) |
| Formato | `CHECK <tabla>_id_formato_ck`: `id BETWEEN campus_id·10⁹+1 AND campus_id·10⁹+999999999` (también en el registro) |
| Campus del nodo | `CHECK <tabla>_campus_ck`: `campus_id = <campus del esquema>`; el disparador también rechaza otro campus |
| id explícito | rechazado (`23514`). Solo con `SET sigtec.permitir_id_explicito = on` **y** siendo miembro del rol `sigtec_mantenimiento_id` (si no: `42501`); además el id debe haber sido emitido por la secuencia y no estar en el registro |
| Eliminación | el registro conserva el id del objeto eliminado: **un id nunca se reutiliza** |
| Inmutabilidad | disparador `trg_20_proteger_identificador` (`BEFORE UPDATE`) rechaza cambiar `id` o `campus_id` (`23514`) |
| Replicación | las copias del central reciben el id ya asignado (no tienen secuencia, disparadores ni registro) |

Ejemplos verificados: primer objeto de Cartago `1000000001`; primero de San Carlos
`3000000001`; segundo de San Carlos `3000000002` aunque sea de otra capa.

## 4. Columnas comunes (las ocho tablas)

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `id` | `bigint` | NO | Identificador global (PK). Inmutable. Sin DEFAULT: lo asigna el disparador. |
| `campus_id` | `smallint` | NO | Campus propietario (1 Cartago, 2 San José, 3 San Carlos, 4 Alajuela, 5 Limón). DEFAULT = campus del esquema. Inmutable. |
| `geom` | `geometry(<tipo>, 5367)` | NO | Geometría; `CHECK NOT ST_IsEmpty(geom) AND ST_IsValid(geom)` (líneas además `ST_Length > 0`). Índice GiST. |

`REPLICA IDENTITY`: la de omisión (clave primaria `id`), suficiente para replicar `UPDATE` y `DELETE`.

## 5. Capas

### 5.1 `edificios` — Polygon

| Columna | Tipo | Nulo | Restricción / dominio | Significado |
|---|---|---|---|---|
| `nombre` | `varchar(120)` | NO | no vacío | Nombre del edificio |
| `codigo` | `varchar(30)` | NO | no vacío, **único en el campus** | Código institucional |
| `area` | `numeric(12,2)` | NO | `> 0` | Área de la huella, m² |
| `pisos` | `smallint` | NO | `1 .. 30` | Cantidad de pisos |

### 5.2 `carreteras` — LineString

| Columna | Tipo | Nulo | Restricción / dominio | Significado |
|---|---|---|---|---|
| `nombre` | `varchar(120)` | NO | no vacío | Nombre de la vía |
| `tipo` | `varchar(30)` | NO | `principal`, `secundaria`, `interna`, `servicio`, `acceso` | Clase de vía |
| `superficie` | `varchar(30)` | NO | `asfalto`, `concreto`, `lastre`, `adoquin`, `tierra` | Material de rodadura |

### 5.3 `aceras` — LineString

| Columna | Tipo | Nulo | Restricción / dominio | Significado |
|---|---|---|---|---|
| `material` | `varchar(30)` | NO | `concreto`, `adoquin`, `asfalto`, `lastre`, `otro` | Material |
| `ancho` | `numeric(5,2)` | NO | `0 < ancho ≤ 20` | Ancho útil, m |
| `condicion` | `varchar(20)` | NO | `buena`, `regular`, `mala` | Estado |

### 5.4 `parqueos` — Polygon

| Columna | Tipo | Nulo | Restricción / dominio | Significado |
|---|---|---|---|---|
| `capacidad` | `integer` | NO | `> 0` | Espacios totales |
| `tipo` | `varchar(30)` | NO | `general`, `estudiantes`, `funcionarios`, `visitantes`, `motocicletas`, `bicicletas`, `discapacidad` | Usuarios del parqueo |
| `disponibilidad` | `integer` | NO | `0 ≤ disponibilidad ≤ capacidad` | Espacios disponibles |

### 5.5 `zonas_verdes` — Polygon

| Columna | Tipo | Nulo | Restricción / dominio | Significado |
|---|---|---|---|---|
| `area` | `numeric(12,2)` | NO | `> 0` | Área, m² |
| `tipo_vegetacion` | `varchar(30)` | NO | `cesped`, `jardin`, `arbustos`, `arboles`, `bosque`, `mixta` | Vegetación predominante |

### 5.6 `puntos_interes` — Point

| Columna | Tipo | Nulo | Restricción / dominio | Significado |
|---|---|---|---|---|
| `nombre` | `varchar(120)` | NO | no vacío | Nombre |
| `tipo` | `varchar(30)` | NO | `cajero`, `laboratorio`, `soda`, `biblioteca`, `auditorio`, `oficina`, `parada_bus`, `servicio_medico`, `otro` | Clase de punto (cajeros, laboratorios, sodas…) |
| `descripcion` | `text` | SÍ | — | Descripción libre |

### 5.7 `iluminacion` — Point

| Columna | Tipo | Nulo | Restricción / dominio | Significado |
|---|---|---|---|---|
| `codigo` | `varchar(30)` | NO | no vacío, **único en el campus** | Código de la luminaria |
| `potencia` | `integer` | NO | `1 .. 2000` | Potencia, W |
| `estado` | `varchar(20)` | NO | `funcional`, `averiada`, `mantenimiento`, `fuera_servicio` | Estado |

### 5.8 `accesibilidad` — LineString

| Columna | Tipo | Nulo | Restricción / dominio | Significado |
|---|---|---|---|---|
| `tipo` | `varchar(30)` | NO | `rampa`, `paso_accesible`, `ruta_accesible`, `ascensor`, `pasamanos`, `guia_podotactil` | Elemento accesible (rampas, pasos accesibles…) |
| `condicion` | `varchar(20)` | NO | `buena`, `regular`, `mala` | Estado |
| `descripcion` | `text` | SÍ | — | Descripción libre |

## 6. Esquema `ops` (cada nodo)

| Tabla | Contenido |
|---|---|
| `ops.schema_migrations` | versión y SHA-256 de cada migración aplicada |
| `ops.node_info` | una fila: `node_code`, `node_host`, `campus_id`, `campus_nombre`, `local_schema`, `srid` |
| `ops.seed_runs` | conjuntos de datos de prueba cargados (`datos_sinteticos_v1`) |
| `ops.recovery_markers` | marcas de las pruebas PITR (A, B, RECUPERADA) con LSN y hora |
| `ops.identificadores_globales` | (campus, migración 0103) un registro por id emitido: `id` (PK), `campus_id`, `capa`, `origen` (`migracion_0103` o `insercion`), `registrado_en`, `sesion`. Sin acceso para PUBLIC; no se publica |

## 7. Datos de prueba

`sql/seed/datos_sinteticos_v1.sql`: **41 objetos sintéticos por campus** (205 en total):
6 edificios, 4 carreteras, 5 aceras, 4 parqueos, 4 zonas verdes, 6 puntos de interés,
8 luminarias y 4 elementos de accesibilidad. Se dibujan en metros alrededor de una coordenada
de referencia **aproximada** de cada campus (EPSG:4326 → 5367). Los nombres llevan el sufijo
"(Campus, sintético)" y las descripciones indican "Dato sintético de prueba".
**No representan infraestructura real del TEC.** Códigos: `CA-`, `SJ-`, `SC-`, `AL-`, `LI-`.

| Campus | Referencia aproximada (lon, lat) |
|---|---|
| Cartago | −83.9126, 9.8558 |
| San José | −84.0757, 9.9386 |
| San Carlos | −84.510307, 10.362791 (ejemplo del contrato técnico) |
| Alajuela | −84.2116, 10.0163 |
| Limón | −83.0322, 9.9907 |

Validación reutilizable: `sql/checks/validacion_capas.sql` (nulas, vacías, SRID, tipo,
validez, campus, formato de id, duplicados por capa) y `sql/checks/verificar_registro_ids.sql`
(ids repetidos entre capas y objetos sin registro).
