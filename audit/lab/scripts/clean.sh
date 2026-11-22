#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · LIMPIEZA DESTRUCTIVA (separada de las operaciones normales)
#
#   scripts/clean.sh                 detiene y ELIMINA contenedores, red y TODOS
#                                    los volúmenes del proyecto (datos, WAL archivado,
#                                    respaldos, instancia recuperada)
#   scripts/clean.sh --recovery-only elimina solo la instancia aislada pg-recovery
#                                    y sus volúmenes (los seis nodos no se tocan)
#   --yes                            omite la pregunta (solo para automatización)
#
# Solo afecta recursos con el prefijo del proyecto (${COMPOSE_PROJECT_NAME:-sigtec}_*).
# No toca .env, el código fuente ni otros proyectos Docker.
# =====================================================================
set -eu
. "$(cd "$(dirname "$0")" && pwd)/lib/host.sh"
load_env

MODE=all; YES=0
for a in "$@"; do
    case "$a" in
        --recovery-only) MODE=recovery ;;
        --yes) YES=1 ;;
        *) h_die "opción desconocida: $a" ;;
    esac
done

if [ "$MODE" = recovery ]; then
    vols="$(volume_name pgdata_recovery) $(volume_name walarchive_recovery)"
    what="la instancia de recuperación pg-recovery y sus volúmenes: $vols"
else
    vols="$(docker volume ls -q --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME" | tr '\n' ' ')"
    what="TODOS los contenedores y volúmenes del proyecto '$COMPOSE_PROJECT_NAME': $vols"
fi

echo "Se eliminará $what"
echo "Esta operación NO se puede deshacer."
if [ "$YES" != 1 ]; then
    printf "Escriba ELIMINAR para continuar: "
    read -r answer
    [ "$answer" = "ELIMINAR" ] || { echo "Cancelado."; exit 1; }
fi

if [ "$MODE" = recovery ]; then
    compose --profile recovery rm -sf pg-recovery >/dev/null 2>&1 || true
    for v in $vols; do docker volume rm "$v" >/dev/null 2>&1 && echo "eliminado $v" || true; done
else
    compose --profile recovery --profile tools down --volumes --remove-orphans
fi
echo "Limpieza terminada."
