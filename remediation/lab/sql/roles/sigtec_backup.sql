-- =====================================================================
-- SIG-TEC · rol de respaldo (se sincroniza en cada instalación; idempotente)
--
-- sigtec_backup: privilegio mínimo para
--   * pg_basebackup  -> atributo REPLICATION (+ regla "host replication" en pg_hba.conf)
--   * pg_dump        -> rol predefinido pg_read_all_data (lectura de todas las tablas/secuencias)
-- No es superusuario, no crea bases ni roles y no puede escribir datos.
--
-- La contraseña se lee de la variable de entorno SIGTEC_BACKUP_PASSWORD
-- (generada en .env por scripts/setup.sh); nunca se versiona.
-- =====================================================================
\getenv backup_password SIGTEC_BACKUP_PASSWORD
\if :{?backup_password}
\else
  \echo 'ERROR: falta SIGTEC_BACKUP_PASSWORD'
  \quit 3
\endif

SELECT NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sigtec_backup') AS crear_rol \gset
\if :crear_rol
  CREATE ROLE sigtec_backup;
\endif

ALTER ROLE sigtec_backup WITH LOGIN REPLICATION NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT
    CONNECTION LIMIT 8 PASSWORD :'backup_password';
GRANT pg_read_all_data TO sigtec_backup;
COMMENT ON ROLE sigtec_backup IS 'SIG-TEC: respaldos (pg_dump / pg_basebackup). Solo lectura + REPLICATION.';
