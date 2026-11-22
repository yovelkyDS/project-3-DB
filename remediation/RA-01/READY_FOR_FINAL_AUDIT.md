# RA-01 — instrucciones para la auditoría final

Este documento indica cómo repetir **de forma independiente** RA-01 y comprobar su corrección.
No declara aprobado el proyecto: esa certificación corresponde a la auditoría.

## 1. Qué se corrigió (resumen)

| Antes | Ahora |
|---|---|
| `make migrate NODE=recovery` imprimía `nodo inválido: recovery` y devolvía **0** (el error de `nodes_expand` se perdía dentro de `for node in $(...)`) | El destino `recovery` es explícito; los destinos se expanden en una asignación que detiene el script; cada clase de fallo tiene su código (2, 3, 4, 5, 1) |
| `pg-recovery` original con 0101/0102, sin registro: dos conexiones de un editor confirmaban el mismo id en dos capas | `make migrate NODE=recovery` aplica 0103 tomando la identidad de la copia, con inspección, respaldo previo validado y verificación posterior; `pg-recovery` original migrada y verificada |
| `make recovery-status` aceptaba la copia antigua con un mensaje informativo | `verify.sh` falla (código 1, "NO APTA") si faltan migraciones o 0103 no está operativa |
| Las 733 pruebas no miraban `pg-recovery` | `[2b] test_recovery_migracion.sh` (PITR real anterior a 0103) y `[2c]` (la instancia en ejecución debe estar apta) |

Detalle: [RA01_REPORT.md](RA01_REPORT.md) y [RA01_TESTS.md](RA01_TESTS.md).

## 2. Repetir RA-01 desde un respaldo anterior a 0103 (laboratorio)

El respaldo físico verificado del `pg-recovery` original **antes** de migrarlo está en el volumen
`sigtec_backups`: `/backups/recovery_pre_ra01/20261120T225613Z/` (`data/` + `sigtec.dump`).
El laboratorio es `remediation/lab` (proyecto `sigtec_remed`, puertos 57430–57436, imagen
`sigtec-remed/postgis:17.12-3.5.4`).

```bash
# a) Recrear SOLO el pg-recovery del laboratorio desde esa copia (origen en solo lectura).
#    --alinear-clave: el clon trae la contraseña de postgres del proyecto original.
bash remediation/RA-01/scripts/clone_recovery_into_lab.sh remediation/lab 20261120T225613Z --alinear-clave
```

```bash
# b) Reproducción con el código actual: RA-01a (migración) y RA-01b (F-02 en la recuperada)
bash remediation/RA-01/scripts/reproduce_ra01.sh remediation/lab /tmp/ra01_reproduccion.log
```

Esperado: `RESULTADO RA-01a: DEFECTO NO REPRODUCIDO (código 0 y 0103 aplicada)` y
`RESULTADO RA-01b: DEFECTO NO REPRODUCIDO (0 fila(s))`.

Para ver el defecto **antes** de la corrección, ejecute b) con el código anterior (por ejemplo,
la instantánea `audit/lab/` copiada a otro laboratorio): RA-01a y RA-01b quedan REPRODUCIDOS,
como en `remediation/RA-01/evidence/02_reproduccion_antes/`.

c) `test_recovery_lab.sh` (56 comprobaciones, `evidence/03_lab_pruebas/`) usa el contenedor real
`pg-recovery` del laboratorio. Cubre:

* destinos inválidos;
* credenciales rechazadas;
* duplicados que detienen la migración sin cambios;
* instancia detenida;
* migración con respaldo previo;
* preservación de datos e identidad;
* idempotencia;
* `verify` apta;
* ataques del editor;
* carrera autorizada;
* 8 conexiones concurrentes;
* reinicio.

Su precondición es un clon **sin** alinear la clave que ya tenga el id repetido. Ese duplicado lo
dejó `reproduce_ra01.sh` ejecutado con el código **anterior** (evidencia 02). Con el código actual,
`reproduce_ra01.sh` migra antes de intentar la carrera, así que no puede volver a crear esa
precondición. Para repetir esos mismos estados desde cero, sin preparación manual, use la suite
del §3 (`test_recovery_migracion.sh`). Construye una copia anterior a 0103 por PITR, crea el
duplicado con dos conexiones solapadas y comprueba los mismos casos con los códigos exactos del
script.

## 3. Suite automática (no toca nodos en servicio)

```bash
cd remediation/lab && bash tests/run_tests.sh --full
```

Esperado: `RESUMEN: 392 PASS`, `RESUMEN respaldos: 36 PASS`, `RESUMEN identificadores: 272 PASS`,
`RESUMEN recuperación RA-01: 65 PASS`, `recovery.migraciones_y_registro` PASS (si `pg-recovery`
está en ejecución) y `RESULTADO: todas las pruebas pasaron`.

Solo la suite RA-01:

```bash
cd remediation/lab && docker compose --profile tools run --rm -T sigtec-tools tests/container/test_recovery_migracion.sh
```

Hace un PITR real en clústeres temporales hacia un instante **anterior** a 0103 (el origen se
migra después del objetivo), reproduce F-02 en la copia sin migrar, comprueba los códigos 1–5
con el script real, la migración, la idempotencia, los ataques, la concurrencia y el reinicio.

Instalación desde cero en un laboratorio nuevo (proyecto `sigtec_ra01`, puertos 57440–57446,
imagen `sigtec-ra01/…`, sin `.env` previo). La secuencia es setup → suite → respaldos →
restore-test → PITR con paso 9b → `auto.conf` sin objetivo → suite con `[2c]` → retención:

```bash
bash remediation/RA-01/scripts/lab_instalacion_limpia.sh /tmp/ra01_limpia "" sigtec_ra01
```

Resultado obtenido: `evidence/08b_lab_instalacion_limpia/`. El laboratorio `sigtec_remed` no sirve
para reinstalar desde cero mientras exista el contenedor detenido `sigtec_reaudit_pitr`, que retiene
dos de sus volúmenes (`evidence/08a_*`).

## 4. Comprobaciones de solo lectura sobre los originales

```bash
make recovery-status                      # "apta para entregar", código 0
docker compose --profile tools run --rm -T sigtec-tools -c '. scripts/lib/db.sh
  psql_su recovery -v schema=local_san_carlos -v campus_id=3 -f sql/checks/verificar_0103.sql'
make migrate NODE=nodo_inexistente; echo $?   # distinto de 0, sin conectarse a ningún nodo
make migrate NODE=recovery; echo $?           # 0, "ninguna pendiente" (no reaplica nada)
```

## 5. Ideas para intentar romperlo

* `make migrate NODE=recovery` con `pg-recovery` detenida, en pausa de recuperación, o con
  `SIGTEC_RECOVERY_INFO` de otro campus.
* Un id repetido introducido en la copia antes de migrar.
* Una migración posterior que falle a mitad (error SQL o de permisos): no debe quedar registrada
  ni dejar objetos.
* Carreras con dos roles autorizados en la recuperada migrada.
