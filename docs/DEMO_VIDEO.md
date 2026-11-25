# Guion del video — segmento del Integrante 1 (≈ 6–8 min)

Preparación (fuera de cámara): `make up` y `make status` con los seis nodos `healthy`.
Si se va a repetir la demostración PITR, `make recovery-clean` antes de grabar. Use una
terminal con letra grande; no muestre el contenido de `.env`.

| # | Qué mostrar | Comando | Qué decir / señalar |
|---|---|---|---|
| 1 | Arquitectura | `docs/ARCHITECTURE.md` (diagrama) | Seis nodos, un esquema local por campus, central para autenticación y consolidación; qué es del Integrante 1 y qué queda para 2 y 3 |
| 2 | Nodos en ejecución | `make ps` | Seis contenedores `healthy`, puertos 55430–55435 solo en 127.0.0.1, volúmenes persistentes |
| 3 | Versiones | `make verify NODE=central` | PostgreSQL 17.12, PostGIS 3.5.4, `wal_level=logical`, archivado sin fallos |
| 4 | Modelo y datos | `make verify NODE=san_carlos` | Ocho capas, filas por capa, todas las columnas de validación en 0 y estado OK |
| 5 | SRID y geometría | `make psql NODE=san_carlos` y luego `\d local_san_carlos.edificios` · `SELECT id, nombre, ST_AsText(geom) FROM local_san_carlos.puntos_interes LIMIT 3;` | `geometry(Polygon,5367)`, CHECK de validez, índice GiST; coordenadas en metros CRTM05 |
| 6 | Identificadores globales | En la misma consola: `INSERT INTO local_san_carlos.puntos_interes (nombre,tipo,geom) SELECT 'Demo video','otro',geom FROM local_san_carlos.puntos_interes LIMIT 1 RETURNING id;` y luego `UPDATE local_san_carlos.puntos_interes SET id = id + 1 WHERE nombre='Demo video';` | id = 3·10⁹ + consecutivo; el UPDATE falla con "inmutable". Borrar la fila de demostración al terminar |
| 7 | Pruebas automatizadas | `make test` | Resumen PASS/FAIL; registro en `evidence/tests/` |
| 8 | Respaldo lógico | `make backup-logical NODE=san_carlos` y `make restore-logical-test NODE=san_carlos` | `pg_dump` con el rol `sigtec_backup`, SHA-256, restauración en clúster temporal: VÁLIDO |
| 9 | Respaldo físico | `make backup-physical NODE=san_carlos` | `pg_basebackup` + `pg_verifybackup`: "backup successfully verified" |
| 10 | Falla + PITR | `make pitr-demo` | Narrar los pasos mientras corren: cambio A, instante objetivo, cambio B, archivado del WAL, `SIGKILL` del nodo, recuperación en `pg-recovery` |
| 11 | Resultado PITR | `evidence/pitr/pitr_<corrida>.md` | A presente, B ausente, "recovery stopping before commit", nueva línea de tiempo, nodo original intacto |
| 12 | Instancia recuperada | `make migrate NODE=recovery` y `make recovery-status` | Migraciones al día, ocho capas válidas, registro de ids íntegro y "apta para entregar" en la instancia aislada (puerto 55436) |
| 13 | Límites | — | La reincorporación a la replicación depende del Integrante 2 y no se demuestra aquí; la geografía es de OpenStreetMap; iluminación y accesibilidad incluyen demostración sintética (DATOS_GEOGRAFICOS.md) |

Duraciones aproximadas observadas: `make pitr-demo` ≈ 1 min; `make test` ≈ 1 min;
respaldo + prueba de un nodo ≈ 15 s.
