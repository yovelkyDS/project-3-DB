#!/usr/bin/env bash
# =====================================================================
# F-01 por la ruta del HOST (Makefile -> scripts/backup/run.sh -> contenedor).
#   remediation/scripts/test_backup_host_paths.sh <laboratorio>
# Desincroniza a propósito la contraseña de sigtec_backup en el nodo central
# DEL LABORATORIO (no en .env), comprueba que make/run.sh devuelvan error y no
# publiquen nada, y la vuelve a sincronizar con make migrate.
# =====================================================================
set -u
LAB="$(cd "${1:?laboratorio}" && pwd)"; cd "$LAB"
PROJECT="$(sed -n 's/^COMPOSE_PROJECT_NAME=//p' .env)"
[ -n "$PROJECT" ] && [ "$PROJECT" != sigtec ] || { echo "negado: no es un laboratorio"; exit 2; }
pass=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS|$1|$4"; pass=$((pass+1)); else echo "FAIL|$1|esperado $3, obtenido $2 ($4)"; fail=$((fail+1)); fi; }
count() { docker compose --profile tools run --rm -T sigtec-tools -c "ls -1d /backups/$1/central/*/ 2>/dev/null | wc -l" 2>/dev/null | tr -d ' \r'; }

L0="$(count logical)"; P0="$(count physical)"
docker exec -u postgres "$PROJECT-pg-central-1" psql -X -q -d sigtec -c \
  "ALTER ROLE sigtec_backup PASSWORD '$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 24)'"
echo "contraseña de sigtec_backup desincronizada en $PROJECT-pg-central-1"

make backup-logical NODE=central > /tmp/remed_make_l.log 2>&1; rc=$?
[ "$rc" != 0 ] && r=error || r=exito; chk make.backup_logical_autenticacion_invalida "$r" error "rc=$rc"
grep -q 'resultado: ERROR' /tmp/remed_make_l.log && r=si || r=no; chk run_sh.informa_error_logico "$r" si "run.sh imprimió 'resultado: ERROR'"
make backup-physical NODE=central > /tmp/remed_make_p.log 2>&1; rc=$?
[ "$rc" != 0 ] && r=error || r=exito; chk make.backup_physical_autenticacion_invalida "$r" error "rc=$rc"
make backup NODE=central > /tmp/remed_make_b.log 2>&1; rc=$?
[ "$rc" != 0 ] && r=error || r=exito; chk make.backup_completo_se_detiene "$r" error "rc=$rc"
grep -q 'pg_basebackup' /tmp/remed_make_b.log && r=continuo || r=detenido; chk make.no_ejecuta_etapa_dependiente "$r" detenido "make backup no siguió a la copia física tras fallar pg_dump"
chk publicados_logicos_sin_cambio "$(count logical)" "$L0" "respaldos lógicos publicados de central"
chk publicados_fisicos_sin_cambio "$(count physical)" "$P0" "copias físicas publicadas de central"

make migrate NODE=central > /tmp/remed_make_m.log 2>&1; echo "contraseña resincronizada con make migrate (rc=$?)"
make backup NODE=central > /tmp/remed_make_ok.log 2>&1; rc=$?
chk make.backup_valido "$rc" 0 "tras resincronizar"
chk publicado_logico_nuevo "$(count logical)" "$((L0 + 1))" "un respaldo lógico nuevo"
chk publicado_fisico_nuevo "$(count physical)" "$((P0 + 1))" "una copia física nueva"
echo "----"; echo "RESUMEN ruta host: $pass PASS, $fail FAIL"
for f in l p b m ok; do echo "== /tmp/remed_make_$f.log"; cat /tmp/remed_make_$f.log; done | sed 's/^/    /' >&2
rm -f /tmp/remed_make_*.log
[ "$fail" = 0 ]
