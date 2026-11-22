-- SIG-TEC · pruebas de infraestructura (los seis nodos)
-- Variables: :node  :campus_id ('' en el central)
SELECT pg_temp.t(:'node' || '.base_sigtec', current_database() = 'sigtec', current_database());
SELECT pg_temp.t(:'node' || '.postgresql_17_12', current_setting('server_version') LIKE '17.12%', current_setting('server_version'));
SELECT pg_temp.t(:'node' || '.postgis_3_5_4',
                 (SELECT extversion FROM pg_extension WHERE extname = 'postgis') = '3.5.4' AND postgis_lib_version() = '3.5.4',
                 'ext=' || coalesce((SELECT extversion FROM pg_extension WHERE extname = 'postgis'), 'ausente') || ' lib=' || postgis_lib_version());
SELECT pg_temp.t(:'node' || '.postgis_funciona',
                 ST_SRID(ST_Transform(ST_SetSRID(ST_MakePoint(-84.510307, 10.362791), 4326), 5367)) = 5367,
                 ST_AsText(ST_SnapToGrid(ST_Transform(ST_SetSRID(ST_MakePoint(-84.510307, 10.362791), 4326), 5367), 0.01)));
SELECT pg_temp.t(:'node' || '.epsg_5367', EXISTS (SELECT 1 FROM spatial_ref_sys WHERE srid = 5367 AND auth_name = 'EPSG'),
                 (SELECT split_part(srtext, '"', 2) FROM spatial_ref_sys WHERE srid = 5367));
SELECT pg_temp.t(:'node' || '.wal_level_logical', current_setting('wal_level') = 'logical', current_setting('wal_level'));
SELECT pg_temp.t(:'node' || '.slots_y_emisores',
                 current_setting('max_wal_senders')::int >= 10 AND current_setting('max_replication_slots')::int >= 10
                 AND current_setting('max_logical_replication_workers')::int >= 4,
                 format('senders=%s slots=%s logical_workers=%s', current_setting('max_wal_senders'),
                        current_setting('max_replication_slots'), current_setting('max_logical_replication_workers')));
SELECT pg_temp.t(:'node' || '.archive_mode', current_setting('archive_mode') = 'on'
                 AND current_setting('archive_command') LIKE '%sigtec-archive-wal%', current_setting('archive_command'));
SELECT pg_temp.t(:'node' || '.archivado_sin_fallos', failed_count = 0,
                 format('archivados=%s fallidos=%s ultimo=%s', archived_count, failed_count, coalesce(last_archived_wal, '-')))
FROM pg_stat_archiver;
SELECT pg_temp.t(:'node' || '.data_checksums', current_setting('data_checksums') = 'on', current_setting('data_checksums'));
SELECT pg_temp.t(:'node' || '.scram', current_setting('password_encryption') = 'scram-sha-256', current_setting('password_encryption'));
SELECT pg_temp.t(:'node' || '.tls_conexion_actual', ssl, coalesce(version, 'sin TLS'))
FROM pg_stat_ssl WHERE pid = pg_backend_pid();
SELECT pg_temp.t(:'node' || '.node_info',
                 (SELECT node_code = :'node' AND campus_id IS NOT DISTINCT FROM NULLIF(:'campus_id', '')::smallint FROM ops.node_info),
                 (SELECT node_code || ' campus_id=' || coalesce(campus_id::text, 'NULL') FROM ops.node_info));
SELECT pg_temp.t(:'node' || '.rol_respaldo_minimo',
                 r.rolreplication AND r.rolcanlogin AND NOT r.rolsuper AND NOT r.rolcreatedb AND NOT r.rolcreaterole
                 AND pg_has_role('sigtec_backup', 'pg_read_all_data', 'USAGE'),
                 format('replication=%s super=%s pg_read_all_data=%s', r.rolreplication, r.rolsuper,
                        pg_has_role('sigtec_backup', 'pg_read_all_data', 'USAGE')))
FROM pg_roles r WHERE r.rolname = 'sigtec_backup';
SELECT pg_temp.t(:'node' || '.migraciones', count(*) >= CASE WHEN :'campus_id' = '' THEN 2 ELSE 4 END, string_agg(version, ',' ORDER BY version))
FROM ops.schema_migrations;
