-- =====================================================================
-- SIG-TEC · PLANTILLA para la reincorporación de un nodo RECUPERADO (Integrante 2)
-- (NO se aplica automáticamente)
--
-- Problema: tras un PITR, el campus recuperado vuelve a un instante anterior.
-- Los objetos creados después del objetivo (p. ej. el cambio B) pueden existir
-- todavía en las copias del central (local_<campus>.* en pg-central). Si la
-- secuencia del campus recuperado quedó por debajo de esos consecutivos, un
-- INSERT nuevo podría reutilizar un id que el central ya conoce.
-- (PostgreSQL registra las secuencias en el WAL por adelantado — 32 valores —
-- por lo que normalmente queda por encima, pero no está garantizado.)
--
-- Uso en el NODO RECUPERADO, con :max_id = máximo id del campus visto en el central:
--   -- en pg-central:   SELECT max(id) FROM (SELECT id FROM local_san_carlos.edificios UNION ALL ...) t;
--   psql ... -v schema=local_san_carlos -v campus_id=3 -v max_id=3000000051 \
--        -f sql/templates/ajustar_secuencia_tras_recuperacion.sql
-- =====================================================================
SELECT :'schema' || '.objeto_id_seq' AS seq \gset

SELECT coalesce(pg_sequence_last_value(:'seq'::regclass), 0) AS antes,
       (:max_id::bigint - :campus_id::bigint * 1000000000)    AS consecutivo_central;

SELECT setval(:'seq'::regclass,
              greatest(coalesce(pg_sequence_last_value(:'seq'::regclass), 0),
                       :max_id::bigint - :campus_id::bigint * 1000000000,
                       1)) AS despues;
