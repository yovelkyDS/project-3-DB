-- Huella de datos de las ocho capas (solo lectura)
SELECT c.relname AS capa,
       (xpath('/row/n/text()', query_to_xml(format('SELECT count(*) AS n FROM local_san_carlos.%I', c.relname), false, true, '')))[1]::text AS filas,
       (xpath('/row/h/text()', query_to_xml(format('SELECT md5(coalesce(string_agg(t::text, ''|'' ORDER BY t.id), '''')) AS h FROM local_san_carlos.%I t', c.relname), false, true, '')))[1]::text AS md5
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'local_san_carlos' AND c.relkind IN ('r','p')
ORDER BY 1;
SELECT node_code, campus_id, local_schema FROM ops.node_info;
SELECT version FROM ops.schema_migrations ORDER BY 1;
