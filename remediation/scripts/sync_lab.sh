#!/usr/bin/env bash
# Copia el código corregido del proyecto al laboratorio aislado (sin .env, evidencias ni plantilla .env.example del lab)
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; LAB="$ROOT/remediation/lab"
for d in scripts sql tests docker; do rsync -a --delete "$ROOT/$d/" "$LAB/$d/"; done
cp "$ROOT/compose.yaml" "$ROOT/Makefile" "$LAB/"
echo "laboratorio sincronizado: $LAB"
