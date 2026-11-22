#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · comprobación de requisitos del host
#   uso: scripts/check_prereqs.sh [--start-docker] [--quiet]
# Requisitos reales del proyecto en el host: bash, Docker Engine y Docker
# Compose v2. Todo el cliente PostgreSQL (psql, pg_dump, pg_basebackup...)
# corre dentro de la imagen del proyecto. make es opcional.
# Código de salida 0 = listo; 1 = falta algo (se muestran instrucciones).
# =====================================================================
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/lib/nodes.sh"

START_DOCKER=0; QUIET=0
for a in "$@"; do
    case "$a" in --start-docker) START_DOCKER=1 ;; --quiet) QUIET=1 ;; esac
done

ok=0
say()  { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
pass() { say "  [OK]    $*"; }
warn() { say "  [AVISO] $*"; }
fail() { say "  [FALTA] $*"; ok=1; }

detect_os() {
    case "$(uname -s 2>/dev/null)" in
        Darwin) echo macos ;;
        Linux)  if grep -qi microsoft /proc/version 2>/dev/null; then echo wsl; else echo linux; fi ;;
        MINGW*|MSYS*|CYGWIN*) echo windows-bash ;;
        *) echo desconocido ;;
    esac
}
OS="$(detect_os)"
say "SIG-TEC · requisitos (sistema detectado: $OS, $(uname -m 2>/dev/null))"

install_hint() {
    case "$OS" in
        macos) say "          Instale Docker Desktop: https://docs.docker.com/desktop/setup/install/mac-install/  (o: brew install --cask docker)" ;;
        linux) say "          Instale Docker Engine + plugin compose: https://docs.docker.com/engine/install/  (Debian/Ubuntu: sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin)" ;;
        wsl)   say "          Instale Docker Desktop para Windows con integración WSL2: https://docs.docker.com/desktop/features/wsl/" ;;
        *)     say "          Instale Docker Desktop: https://docs.docker.com/get-started/get-docker/" ;;
    esac
}

# 1. bash
pass "bash ${BASH_VERSION}"

# 2. docker CLI
if command -v docker >/dev/null 2>&1; then
    pass "docker CLI $(docker --version 2>/dev/null | sed 's/^Docker version //')"
else
    fail "docker CLI no encontrado"; install_hint
fi

# 3. docker compose v2
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    cv="$(docker compose version --short 2>/dev/null | sed 's/^v//')"
    major="${cv%%.*}"; rest="${cv#*.}"; minor="${rest%%.*}"
    if [ "${major:-0}" -gt 2 ] || { [ "${major:-0}" -eq 2 ] && [ "${minor:-0}" -ge 20 ]; }; then
        pass "docker compose $cv"
    else
        fail "docker compose $cv: se requiere >= 2.20"
    fi
else
    fail "docker compose v2 no disponible (plugin 'docker compose')"; install_hint
fi

# 4. daemon
daemon_up() { docker info >/dev/null 2>&1; }
if command -v docker >/dev/null 2>&1; then
    if ! daemon_up && [ "$START_DOCKER" = 1 ]; then
        say "  ...     Docker está detenido; intentando iniciarlo"
        case "$OS" in
            macos) open -a Docker >/dev/null 2>&1 || true ;;
            linux) if command -v systemctl >/dev/null 2>&1; then
                       systemctl start docker >/dev/null 2>&1 || sudo -n systemctl start docker >/dev/null 2>&1 || true
                   fi ;;
            wsl|windows-bash) command -v powershell.exe >/dev/null 2>&1 && \
                       powershell.exe -NoProfile -Command "Start-Process 'C:\\Program Files\\Docker\\Docker\\Docker Desktop.exe'" >/dev/null 2>&1 || true ;;
        esac
        i=0; while ! daemon_up && [ $i -lt 60 ]; do sleep 3; i=$((i + 1)); done
    fi
    if daemon_up; then
        mem="$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)"
        pass "daemon Docker activo (servidor $(docker info --format '{{.ServerVersion}}' 2>/dev/null), $(( mem / 1024 / 1024 )) MiB, $(docker info --format '{{.Architecture}}' 2>/dev/null))"
        [ "$mem" -lt 3000000000 ] 2>/dev/null && warn "Docker tiene menos de 3 GiB de memoria; seis nodos pueden ir lentos"
    else
        fail "el daemon Docker no responde"
        case "$OS" in
            macos) say "          Abra Docker Desktop (open -a Docker) y vuelva a ejecutar." ;;
            linux) say "          sudo systemctl start docker   (y agregue su usuario al grupo docker: sudo usermod -aG docker \$USER)" ;;
            *)     say "          Inicie Docker Desktop y vuelva a ejecutar." ;;
        esac
    fi
fi

# 5. aleatoriedad para generar contraseñas
if command -v openssl >/dev/null 2>&1 || [ -r /dev/urandom ]; then
    pass "generador de contraseñas disponible ($(command -v openssl >/dev/null 2>&1 && echo openssl || echo /dev/urandom))"
else
    fail "no hay openssl ni /dev/urandom para generar contraseñas"
fi

# 6. make (opcional)
if command -v make >/dev/null 2>&1; then pass "make $(make --version 2>/dev/null | head -1 | sed 's/GNU Make //')"
else warn "make no encontrado (opcional): use los scripts de scripts/ directamente"; fi

# 7. espacio en disco
avail_kb="$(df -Pk "$ROOT" 2>/dev/null | awk 'NR==2{print $4}')"
if [ -n "$avail_kb" ] && [ "$avail_kb" -lt 3000000 ]; then
    warn "menos de 3 GB libres en $(df -Pk "$ROOT" | awk 'NR==2{print $6}')"
else
    pass "espacio en disco suficiente"
fi

# 8. puertos (solo si el proyecto no está corriendo ya)
# Puertos efectivos: variables ya exportadas > .env > .env.example (primera
# instalación). Corrección F-04: antes se revisaban siempre los valores por omisión.
cfg="$ROOT/.env"; [ -f "$cfg" ] || cfg="$ROOT/.env.example"
while IFS='=' read -r k v; do
    case "$k" in
        SIGTEC_PORT_*) eval "[ -n \"\${$k:-}\" ] || export $k=\"\$v\"" ;;
    esac
done < <(grep -E '^SIGTEC_PORT_[A-Z_]+=[0-9]+$' "$cfg" 2>/dev/null)
running=""
if command -v docker >/dev/null 2>&1 && daemon_up; then
    running="$(docker compose --project-directory "$ROOT" -f "$ROOT/compose.yaml" ps -q 2>/dev/null || true)"
fi
if [ -z "$running" ]; then
    busy=""
    for n in $SIGTEC_NODES recovery; do
        p="$(node_port "$n")"
        if command -v lsof >/dev/null 2>&1; then
            lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1 && busy="$busy $p"
        elif command -v ss >/dev/null 2>&1; then
            ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":$p\$" && busy="$busy $p"
        fi
    done
    ports="$(for n in $SIGTEC_NODES recovery; do node_port "$n"; done | tr '\n' ' ')"
    if [ -n "$busy" ]; then fail "puertos ocupados:$busy (cámbielos en .env; configuración leída de ${cfg#"$ROOT"/})"
    else pass "puertos libres: $ports(de ${cfg#"$ROOT"/})"; fi
else
    pass "el proyecto ya está en ejecución (no se revisan puertos)"
fi

# 9. aviso de carpetas sincronizadas
case "$ROOT" in
    *OneDrive*|*Dropbox*|*iCloud*|*"Google Drive"*)
        warn "el proyecto está en una carpeta sincronizada en la nube. Los datos y respaldos viven en volúmenes Docker (no se sincronizan); solo el código fuente está en esta carpeta." ;;
esac

if [ "$ok" = 0 ]; then say "Requisitos: LISTO"; else say "Requisitos: INCOMPLETOS"; fi
exit "$ok"
