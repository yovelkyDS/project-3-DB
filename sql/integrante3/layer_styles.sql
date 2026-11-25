-- Firma compatible con el almacenamiento de estilos PostgreSQL de QGIS 3.x.
-- Los QML se insertan desde scripts/integrante3/manage.py para mantener una
-- sola fuente de verdad en qgis_plugin/sigtec/styles/*.qml.
BEGIN;

CREATE TABLE IF NOT EXISTS public.layer_styles (
    id serial PRIMARY KEY,
    f_table_catalog varchar,
    f_table_schema varchar,
    f_table_name varchar,
    f_geometry_column varchar,
    stylename text,
    styleqml xml,
    stylesld xml,
    useasdefault boolean,
    description text,
    owner varchar(63) DEFAULT CURRENT_USER,
    ui xml,
    update_time timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    type varchar,
    r_raster_column varchar
);

REVOKE ALL ON public.layer_styles FROM PUBLIC;
COMMENT ON TABLE public.layer_styles IS
  'SIG-TEC: estilos institucionales administrados en central y replicados a los campus.';

COMMIT;
