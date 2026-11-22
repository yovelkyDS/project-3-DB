# Dependencias y versiones

## 1. En el equipo anfitrión

| Dependencia | Versión mínima | Uso | Instalación |
|---|---|---|---|
| Docker Engine / Docker Desktop | versión actual (probado con 29.2.1) | Contenedores, red y volúmenes | macOS/Windows: Docker Desktop · Linux: paquete `docker-ce` del repositorio oficial |
| Docker Compose v2 | 2.20 | `compose.yaml` (perfiles, `pull_policy`, anclas) | Incluido en Docker Desktop · Linux: `docker-compose-plugin` |
| bash | 3.2+ | Instalador y scripts (compatibles con el bash de macOS) | Incluido en macOS/Linux · Windows: WSL2 o Git for Windows |
| make | cualquiera | Atajos opcionales | Xcode CLT / `build-essential` / Git for Windows |
| openssl | cualquiera | Opcional; el instalador genera secretos con `openssl` o `/dev/urandom` | Incluido normalmente |

**No** se necesita PostgreSQL, psql, PostGIS ni Python en el anfitrión: todos los clientes
(`psql`, `pg_dump`, `pg_restore`, `pg_basebackup`, `pg_verifybackup`, `pg_archivecleanup`)
corren en el contenedor `sigtec-tools`, construido con la misma imagen que los nodos. Por eso
no hay `requirements.txt`. `scripts/check_prereqs.sh` valida todo y muestra cómo instalar lo
que falte según el sistema operativo.

## 2. Imagen `sigtec/postgis:17.12-3.5.4`

| Componente | Versión | Cómo se fija |
|---|---|---|
| Imagen base | `postgres:17.12-trixie` | Etiqueta **y** digest `sha256:b60e90042aa6b8dbecd58e224b3e36114dbf8ad754465264c2476ad58a86e45c` (`ARG PG_IMAGE` en el Dockerfile) |
| PostgreSQL | 17.12 (Debian 17.12-1.pgdg13+1) | Por la imagen base |
| PostGIS | 3.5.4 | Compilado desde `https://download.osgeo.org/postgis/source/postgis-3.5.4.tar.gz`, SHA-256 `bc960a0395942d58abb8078a09bb901bd49555565532f5246cc28292d9eadb57` comprobado durante la construcción |
| GEOS | 3.15.0 | Paquete del sistema de la imagen base (Debian trixie / PGDG) en el momento de la construcción |
| PROJ | 9.9.0 | Ídem |
| libxml2 / json-c | 2.9.14 / 0.18 | Ídem |

Opciones de compilación de PostGIS: `--without-raster --without-topology
--without-address-standardizer --without-protobuf` (el proyecto solo usa geometría vectorial).
El Dockerfile tiene dos etapas: la de compilación deduce con `ldd`/`dpkg` los paquetes de
ejecución que necesita la extensión y la etapa final instala únicamente esos (más `openssl`
para el certificado TLS).

Las versiones de GEOS/PROJ dependen de los paquetes disponibles al construir; no hay digest de
paquetes Debian. `make versions` registra las efectivas en
[`evidence/versions.txt`](../evidence/versions.txt).

## 3. Versiones registradas en este entorno (20 nov 2026)

| Elemento | Valor |
|---|---|
| Anfitrión | macOS (Darwin 27.0.0, arm64) |
| Docker | 29.2.1 (Docker Desktop, aarch64) |
| Docker Compose | 5.0.2 |
| Imagen construida | `sigtec/postgis:17.12-3.5.4`. El id es local y cambia en cada construcción (PostGIS se compila desde la fuente fijada; el binario no es reproducible bit a bit). Los contenedores originales se crearon con `sha256:cc0beda0…402af`; la etiqueta apunta hoy a `sha256:fd04b3df…e455c` (misma fuente y digest base, ver `remediation/REMEDIATION_REPORT.md`). Consultar con `make versions` |
| Servidor en los seis nodos | PostgreSQL 17.12 · `POSTGIS="3.5.4 2fc837e"` · `GEOS="3.15.0-CAPI-1.21.0"` · `PROJ="9.9.0"` |
| Clientes | psql / pg_dump / pg_basebackup 17.12 |

## 4. Archivos del proyecto que definen dependencias

| Archivo | Contenido |
|---|---|
| `docker/postgis/Dockerfile` | Imagen base con digest, versión y SHA-256 de PostGIS |
| `compose.yaml` | Servicios, imagen local (`pull_policy: never`), volúmenes, red, perfiles |
| `.env.example` | Variables de configuración; los secretos se generan al instalar |
| `scripts/check_prereqs.sh` | Requisitos del anfitrión y versiones mínimas |
