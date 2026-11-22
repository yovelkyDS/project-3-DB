# shellcheck shell=bash
# =====================================================================
# SIG-TEC · catálogo de nodos (fuente única para el host y los contenedores)
# Compatible con bash 3.2 (macOS): sin arreglos asociativos.
# =====================================================================

SIGTEC_NODES="central cartago san_jose san_carlos alajuela limon"
SIGTEC_CAMPUS_NODES="cartago san_jose san_carlos alajuela limon"
SIGTEC_LAYERS="edificios carreteras aceras parqueos zonas_verdes puntos_interes iluminacion accesibilidad"
SIGTEC_SRID=5367
SIGTEC_DB=sigtec

node_valid() {
    case "${1:-}" in
        central|cartago|san_jose|san_carlos|alajuela|limon) return 0 ;;
        *) return 1 ;;
    esac
}

node_is_campus() { [ "${1:-}" != "central" ] && node_valid "${1:-}"; }

# Nombre del servicio Compose = host interno en la red Docker
node_host() { echo "pg-$(echo "$1" | tr '_' '-')"; }

node_campus_id() {
    case "$1" in
        cartago) echo 1 ;; san_jose) echo 2 ;; san_carlos) echo 3 ;;
        alajuela) echo 4 ;; limon) echo 5 ;; central) echo "" ;;
        *) return 1 ;;
    esac
}

node_schema() { node_is_campus "$1" && echo "local_$1" || echo ""; }

node_port() {
    case "$1" in
        central)    echo "${SIGTEC_PORT_CENTRAL:-55430}" ;;
        cartago)    echo "${SIGTEC_PORT_CARTAGO:-55431}" ;;
        san_jose)   echo "${SIGTEC_PORT_SAN_JOSE:-55432}" ;;
        san_carlos) echo "${SIGTEC_PORT_SAN_CARLOS:-55433}" ;;
        alajuela)   echo "${SIGTEC_PORT_ALAJUELA:-55434}" ;;
        limon)      echo "${SIGTEC_PORT_LIMON:-55435}" ;;
        recovery)   echo "${SIGTEC_PORT_RECOVERY:-55436}" ;;
        *) return 1 ;;
    esac
}

node_nombre() {
    case "$1" in
        central)    echo "Nodo central" ;;
        cartago)    echo "Campus Tecnológico Central, Cartago" ;;
        san_jose)   echo "Campus Tecnológico Local San José" ;;
        san_carlos) echo "Campus Tecnológico Local San Carlos" ;;
        alajuela)   echo "Campus Tecnológico Local Alajuela" ;;
        limon)      echo "Campus Tecnológico Local Limón" ;;
        *) return 1 ;;
    esac
}

node_corto() {
    case "$1" in
        central) echo "Central" ;; cartago) echo "Cartago" ;; san_jose) echo "San José" ;;
        san_carlos) echo "San Carlos" ;; alajuela) echo "Alajuela" ;; limon) echo "Limón" ;;
        *) return 1 ;;
    esac
}

# Prefijo de códigos en los datos sintéticos
node_code_prefix() {
    case "$1" in
        cartago) echo CA ;; san_jose) echo SJ ;; san_carlos) echo SC ;;
        alajuela) echo AL ;; limon) echo LI ;; *) return 1 ;;
    esac
}

# Coordenada de referencia APROXIMADA (EPSG:4326: "longitud latitud") usada
# solo para ubicar los datos sintéticos cerca de cada campus.
node_anchor() {
    case "$1" in
        cartago)    echo "-83.9126 9.8558" ;;
        san_jose)   echo "-84.0757 9.9386" ;;
        san_carlos) echo "-84.510307 10.362791" ;;   # ejemplo del contrato técnico
        alajuela)   echo "-84.2116 10.0163" ;;
        limon)      echo "-83.0322 9.9907" ;;
        *) return 1 ;;
    esac
}

# Expande "all" | "campus" | lista de nodos separada por espacios/comas
nodes_expand() {
    local arg="${*:-all}" out="" n
    arg="$(echo "$arg" | tr ',' ' ')"
    for n in $arg; do
        case "$n" in
            all)    out="$out $SIGTEC_NODES" ;;
            campus) out="$out $SIGTEC_CAMPUS_NODES" ;;
            *)      node_valid "$n" || { echo "nodo inválido: $n" >&2; return 2; }
                    out="$out $n" ;;
        esac
    done
    echo $out
}
