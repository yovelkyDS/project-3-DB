#!/bin/bash
set -euo pipefail
root=$(pwd)
args=(docker run --rm --network none --entrypoint bash -v "$root/scripts:/opt/sigtec/scripts:ro" -v "$root/sql:/opt/sigtec/sql:ro" -v sigtec_backups:/original_backups:ro)
for n in central cartago san_jose san_carlos alajuela limon; do args+=(-v "sigtec_walarchive_$n:/archives/$n:ro"); done
"${args[@]}" sigtec/postgis:17.12-3.5.4 -c '
set -euo pipefail
mkdir /backups
cp -a /original_backups/. /backups/
cd /opt/sigtec
for d in /backups/physical/*/*/data; do echo "VERIFY $d"; pg_verifybackup "$d"; done
scripts/backup/logical_restore_test.sh all
scripts/backup/physical_restore_test.sh all
'
