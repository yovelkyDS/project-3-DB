#!/usr/bin/env bash
# SIG-TEC · registra las versiones efectivas (contrato técnico §1) en evidence/versions.txt
set -eu
. "$(cd "$(dirname "$0")" && pwd)/lib/host.sh"
load_env
OUT="$(evidence_file . versions.txt)"
{
    echo "# SIG-TEC · versiones efectivas — $(h_ts)"
    echo "host: $(uname -s) $(uname -r) $(uname -m)"
    echo "docker: $(docker --version)"
    echo "docker compose: $(docker compose version --short)"
    echo "docker server: $(docker info --format '{{.ServerVersion}} ({{.OperatingSystem}}, {{.Architecture}})')"
    echo "imagen: ${SIGTEC_IMAGE:-sigtec/postgis:17.12-3.5.4} id=$(docker image inspect -f '{{.Id}}' "${SIGTEC_IMAGE:-sigtec/postgis:17.12-3.5.4}")"
    echo "imagen base: $(sed -n 's/^ARG PG_IMAGE=//p' "$SIGTEC_ROOT/docker/postgis/Dockerfile")"
    echo "PostGIS fuente: $(sed -n 's/^ARG POSTGIS_VERSION=//p' "$SIGTEC_ROOT/docker/postgis/Dockerfile" | head -1) sha256=$(sed -n 's/^ARG POSTGIS_SHA256=//p' "$SIGTEC_ROOT/docker/postgis/Dockerfile")"
    echo
    tools -c '. scripts/lib/db.sh
      echo "cliente: $(psql --version) / $(pg_dump --version) / $(pg_basebackup --version)"
      for n in $SIGTEC_NODES; do
        echo "--- $n ($(node_host $n))"
        psql_su "$n" -tA -c "SELECT version()" -c "SELECT postgis_full_version()"
      done' 2>/dev/null
} > "$OUT"
cat "$OUT"
