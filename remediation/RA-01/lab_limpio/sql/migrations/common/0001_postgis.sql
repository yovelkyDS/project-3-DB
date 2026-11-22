-- SIG-TEC · migración común 0001
-- PostGIS en la base sigtec. En un volumen nuevo ya lo crea docker/postgis/initdb;
-- esta migración lo garantiza también en bases existentes o restauradas.
CREATE EXTENSION IF NOT EXISTS postgis;

-- EPSG:5367 (CR05 / CRTM05) debe estar disponible en spatial_ref_sys.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.spatial_ref_sys WHERE srid = 5367) THEN
        RAISE EXCEPTION 'SIG-TEC: EPSG:5367 (CR05 / CRTM05) no está en spatial_ref_sys';
    END IF;
END
$$;
