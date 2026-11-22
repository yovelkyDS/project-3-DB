# syntax=docker/dockerfile:1
#
# SIG-TEC — imagen PostgreSQL 17.12 + PostGIS 3.5.4
#
# Por qué se compila PostGIS:
#   * postgis/postgis:17-3.5 solo se publica para amd64 y no fija la versión 3.5.4.
#   * El repositorio PGDG ya no ofrece 3.5.4 (pasó de 3.5.3 a 3.6/3.7).
#   Por eso se parte de la imagen oficial postgres:17.12 (multi-arquitectura, fijada
#   por digest) y se compila PostGIS 3.5.4 desde el tarball oficial de OSGeo,
#   verificado con SHA-256.
#
ARG PG_IMAGE=postgres:17.12-trixie@sha256:b60e90042aa6b8dbecd58e224b3e36114dbf8ad754465264c2476ad58a86e45c

########################################################################
# Etapa 1: compilación de PostGIS
########################################################################
FROM ${PG_IMAGE} AS build

ARG POSTGIS_VERSION=3.5.4
ARG POSTGIS_SHA256=bc960a0395942d58abb8078a09bb901bd49555565532f5246cc28292d9eadb57

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl pkg-config \
        "postgresql-server-dev-${PG_MAJOR}" \
        libgeos-dev libproj-dev libjson-c-dev libxml2-dev; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src
RUN set -eux; \
    curl -fsSL -o postgis.tar.gz "https://download.osgeo.org/postgis/source/postgis-${POSTGIS_VERSION}.tar.gz"; \
    echo "${POSTGIS_SHA256}  postgis.tar.gz" | sha256sum -c -; \
    tar -xzf postgis.tar.gz; \
    cd "postgis-${POSTGIS_VERSION}"; \
    ./configure \
        --without-raster \
        --without-topology \
        --without-address-standardizer \
        --without-protobuf \
        --without-interrupt-tests; \
    # Evitar carreras entre sub-make que generan los mismos archivos SQL temporales.
    make -j1; \
    make install DESTDIR=/out; \
    # Paquetes Debian que proveen las bibliotecas compartidas usadas por PostGIS
    find /out -type f \( -name '*.so' -o -path '*/bin/*' \) -exec ldd {} \; 2>/dev/null \
      | awk '/=> \//{print $3}' | sort -u \
      | xargs -r -n1 realpath | xargs -r dpkg -S 2>/dev/null \
      | cut -d: -f1 | sort -u > /out/sigtec-runtime-packages.txt; \
    cat /out/sigtec-runtime-packages.txt

########################################################################
# Etapa 2: imagen final
########################################################################
FROM ${PG_IMAGE}

ARG POSTGIS_VERSION=3.5.4
LABEL org.opencontainers.image.title="sigtec-postgis" \
      org.opencontainers.image.description="PostgreSQL 17.12 + PostGIS ${POSTGIS_VERSION} para SIG-TEC (TEC, Bases de Datos II)" \
      sigtec.postgres.version="17.12" \
      sigtec.postgis.version="${POSTGIS_VERSION}"

COPY --from=build /out/sigtec-runtime-packages.txt /tmp/sigtec-runtime-packages.txt
RUN set -eux; \
    apt-get update; \
    # openssl: certificado TLS autofirmado de desarrollo; el resto: bibliotecas de PostGIS
    apt-get install -y --no-install-recommends openssl $(grep -v -E '^(libc6|libgcc-s1|libstdc\+\+6)$' /tmp/sigtec-runtime-packages.txt); \
    rm -rf /var/lib/apt/lists/* /tmp/sigtec-runtime-packages.txt

COPY --from=build /out/usr/ /usr/

# Configuración común de los nodos (inmutable dentro de la imagen)
COPY conf/postgresql.conf conf/pg_hba.conf /etc/postgresql/
COPY bin/sigtec-entrypoint bin/sigtec-recovery-entrypoint bin/sigtec-archive-wal /usr/local/bin/
# Se ejecuta SOLO cuando el volumen de datos está vacío (primer arranque)
COPY initdb/ /docker-entrypoint-initdb.d/

RUN set -eux; \
    chmod 0755 /usr/local/bin/sigtec-*; \
    chmod 0644 /etc/postgresql/postgresql.conf /etc/postgresql/pg_hba.conf; \
    install -d -o postgres -g postgres -m 0700 /var/lib/postgresql/wal_archive /var/lib/postgresql/tls; \
    # Comprobación de que la extensión quedó instalada
    test -f "/usr/share/postgresql/${PG_MAJOR}/extension/postgis--${POSTGIS_VERSION}.sql"

ENTRYPOINT ["sigtec-entrypoint"]
CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]
