#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · imprime la ruta del Python incluido en QGIS (PyQGIS)
#   uso: scripts/qgis_python.sh            código 1 si no se encuentra
# Para una ubicación no estándar: QGIS_PYTHON=/ruta/al/python
# =====================================================================
set -u
try() { [ -n "$1" ] && [ -x "$1" ] && { printf '%s\n' "$1"; exit 0; }; }

try "${QGIS_PYTHON:-}"
case "$(uname -s 2>/dev/null)" in
    Darwin)
        for app in /Applications/QGIS-LTR.app /Applications/QGIS*3.44*.app /Applications/QGIS.app; do
            try "$app/Contents/MacOS/python"
        done ;;
    MINGW*|MSYS*|CYGWIN*)
        for d in "/c/Program Files/QGIS 3.44"* "/c/OSGeo4W"; do
            try "$d/bin/python-qgis-ltr.bat"
        done ;;
    *)
        if python3 -c 'import qgis.core' >/dev/null 2>&1; then command -v python3; exit 0; fi ;;
esac
echo "No se encontró el Python de QGIS 3.44 LTR. Instálelo o defina QGIS_PYTHON." >&2
exit 1
