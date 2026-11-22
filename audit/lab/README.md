# SIG-TEC · Infraestructura distribuida PostgreSQL/PostGIS (Integrante 1)

**SIG-TEC: Sistema Distribuido de Gestión de Información Geográfica de los Campus del Tecnológico de Costa Rica** — Tercer Proyecto, Bases de Datos II.

Este repositorio contiene la parte del **Integrante 1 (arquitectura, PostGIS y recuperación)**:
seis nodos PostgreSQL 17.12 + PostGIS 3.5.4 en Docker, el modelo geográfico común de ocho
capas en los cinco campus, identificadores globales, datos de prueba, respaldos lógicos y
físicos, archivado WAL, recuperación a un instante (PITR) y una demostración de falla y
recuperación reproducible. La infraestructura queda lista para que los Integrantes 2 y 3
agreguen replicación, vistas, autenticación y el complemento de QGIS sin reconstruir nada.

| Documento | Contenido |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Topología (Mermaid), red, puertos, arranque, configuración, decisiones técnicas |
| [docs/DATA_DICTIONARY.md](docs/DATA_DICTIONARY.md) | Ocho capas, columnas, tipos, restricciones, SRID, identificadores |
| [docs/BACKUP_RECOVERY.md](docs/BACKUP_RECOVERY.md) | pg_dump, pg_basebackup, WAL, PITR, verificación, errores frecuentes |
| [docs/INTEGRATION.md](docs/INTEGRATION.md) | Contrato e interfaces para los Integrantes 2 y 3 |
| [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) | Manifiesto de dependencias y versiones efectivas |
| [docs/DEMO_VIDEO.md](docs/DEMO_VIDEO.md) | Guion y comandos para grabar el segmento del video |
| [evidence/](evidence/) | Registros reales de instalación, pruebas, respaldos y PITR |

## Tecnologías

PostgreSQL **17.12** · PostGIS **3.5.4** (GEOS 3.15.0, PROJ 9.9.0) · Docker Engine + Docker
Compose v2 · SQL y PL/pgSQL · Bash · herramientas nativas `pg_dump`, `pg_restore`,
`pg_dumpall`, `pg_basebackup`, `pg_verifybackup`, `pg_archivecleanup` · WAL + PITR.
SRID institucional **EPSG:5367 (CR05 / CRTM05)**, en metros.

## Requisitos previos

Solo se necesita en el equipo:

* **Docker** (Docker Desktop en macOS/Windows, Docker Engine en Linux) con **Compose v2 ≥ 2.20**.
* **bash** (incluido en macOS/Linux; en Windows: WSL2 o Git Bash) — o PowerShell con `scripts/setup.ps1`.
* `make` es opcional (atajos). ~3 GB de disco y ~3 GB de memoria para Docker.

No hace falta instalar PostgreSQL, psql ni Python en el host: todas las herramientas cliente
corren dentro de la imagen del proyecto. `scripts/check_prereqs.sh` comprueba todo lo
anterior, intenta iniciar Docker si está detenido y muestra instrucciones de instalación
específicas del sistema operativo si falta algo.

## Instalación desde cero

```bash
scripts/setup.sh
```

En Windows sin bash: `powershell -ExecutionPolicy Bypass -File scripts\setup.ps1`.

El instalador: (1) valida requisitos, (2) crea `.env` y **genera contraseñas aleatorias**
(no las imprime), (3) construye la imagen, (4) crea red y volúmenes e inicia los seis
nodos, (5) espera los healthchecks, (6) aplica las migraciones (PostGIS, esquema `ops`,
esquemas locales, ocho capas, reglas de identificadores, rol de respaldo), (7) carga los
datos de prueba, (8) verifica y (9) muestra un resumen. Es **idempotente**: repetirlo no
borra datos, no reaplica migraciones y no duplica datos de prueba.

La primera vez tarda unos minutos porque compila PostGIS 3.5.4 (ver
[docs/DEPENDENCIES.md](docs/DEPENDENCIES.md)); después la imagen queda en caché.

## Comandos

`make help` lista todo. Los principales:

| Comando | Acción |
|---|---|
| `make setup` | Instalar / actualizar (equivale a `scripts/setup.sh`) |
| `make up` / `make down` / `make restart` | Iniciar / detener (conserva datos) / reiniciar los seis nodos |
| `make status` · `make ps` · `make logs NODE=san_carlos` | Estado, contenedores, logs |
| `make verify NODE=campus` | Versiones, PostGIS y validación de las ocho capas |
| `make test` · `make test-full` | Pruebas automatizadas (`-full` agrega idempotencia y reinicio) |
| `make backup NODE=all` | `pg_dump` + `pg_basebackup` de los nodos indicados |
| `make restore-test NODE=all` | Restaura los últimos respaldos en clústeres temporales aislados y los valida |
| `make backup-list` · `make wal-retention` | Inventario de respaldos/WAL · retención (simulación; `APPLY=1`) |
| `make pitr-demo` | Falla simulada + PITR de San Carlos en la instancia aislada `pg-recovery` |
| `make psql NODE=cartago` | Consola `psql` como superusuario (`NODE=recovery` para la instancia recuperada) |
| `make versions` | Registra versiones efectivas en `evidence/versions.txt` |

`NODE` acepta `all`, `campus`, `central`, `cartago`, `san_jose`, `san_carlos`, `alajuela`, `limon`.

## Puertos y conexiones

Publicados solo en `127.0.0.1` (cambie `SIGTEC_BIND_ADDRESS` en `.env` si QGIS corre en otra máquina).

| Nodo | Host Docker (red `sigtec_net`, puerto 5432) | Puerto en el host | campus_id | Esquema local |
|---|---|---|---|---|
| Central | `pg-central` | 55430 | — | — |
| Cartago | `pg-cartago` | 55431 | 1 | `local_cartago` |
| San José | `pg-san-jose` | 55432 | 2 | `local_san_jose` |
| San Carlos | `pg-san-carlos` | 55433 | 3 | `local_san_carlos` |
| Alajuela | `pg-alajuela` | 55434 | 4 | `local_alajuela` |
| Limón | `pg-limon` | 55435 | 5 | `local_limon` |
| Recuperación (aislada) | `pg-recovery` | 55436 | (la del nodo restaurado) | — |

Base de datos `sigtec` en todos. Usuario administrador `postgres` con la contraseña
`POSTGRES_PASSWORD` de `.env`. Ejemplo desde el host (si tiene psql instalado):
`psql "host=127.0.0.1 port=55433 dbname=sigtec user=postgres sslmode=require"`.
Las conexiones usan SCRAM-SHA-256 y TLS (certificado autofirmado de desarrollo).

## Verificar y probar

```bash
make verify          # resumen por nodo y por capa
make test-full       # 300+ comprobaciones; registro en evidence/tests/
```

Las pruebas cubren contenedores, healthchecks, puertos, volúmenes, versiones, PostGIS,
WAL/archivado, TLS, roles, las ocho capas en los cinco campus, tipos y SRID, validez
geométrica, fórmula e inmutabilidad de identificadores, unicidad global de ids,
restricciones, compatibilidad de la plantilla del central, secretos fuera del repositorio,
idempotencia del arranque y persistencia tras reiniciar.

## Limpieza segura

* `make down` detiene y elimina contenedores; **los volúmenes y datos se conservan**.
* `make recovery-clean` elimina solo la instancia aislada `pg-recovery` (pide escribir `ELIMINAR`).
* `make clean` elimina contenedores **y todos los volúmenes del proyecto** (datos, WAL
  archivado, respaldos). Pide confirmación explícita. Solo toca recursos `sigtec_*`.

Nunca use `docker compose down -v` como operación normal.

## Estado de los componentes

| Componente | Responsable | Estado |
|---|---|---|
| Seis nodos PostgreSQL/PostGIS, red, volúmenes, healthchecks, TLS | Integrante 1 | **Implementado y probado** |
| Modelo de ocho capas × cinco campus, SRID 5367, ids globales | Integrante 1 | **Implementado y probado** |
| Datos de prueba (sintéticos, 41 objetos por campus) | Integrante 1 | **Implementado y probado** |
| pg_dump / restauración lógica (seis nodos) | Integrante 1 | **Implementado y probado** |
| pg_basebackup / archivado WAL / recuperación física (seis nodos) | Integrante 1 | **Implementado y probado** |
| Falla simulada + PITR (San Carlos, instancia aislada) | Integrante 1 | **Implementado y probado** |
| Parámetros habilitantes de replicación lógica + plantilla de tablas destino del central | Integrante 1 | **Listo para el Integrante 2** |
| Publicaciones/suscripciones, `global`, vistas `qgis`, INSTEAD OF, transacción distribuida | Integrante 2 | Pendiente (fuera de este alcance) |
| Reincorporación del nodo recuperado a la replicación | Integrante 2 | **No demostrada** (requiere la replicación) |
| `auth`, cuentas `qgis_*`, complemento PyQGIS, estilos `layer_styles`, manual | Integrante 3 | Pendiente (fuera de este alcance) |

Los datos geográficos de prueba son **sintéticos**: no representan infraestructura real del TEC.
