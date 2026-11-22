-- =====================================================================
-- SIG-TEC · validación reutilizable de las ocho capas de un campus
--   psql -v schema=local_san_carlos -v campus_id=3 -f sql/checks/validacion_capas.sql
-- También sirve para un nodo recuperado o restaurado.
-- Una fila por capa; estado = OK si todas las comprobaciones dan 0.
-- =====================================================================
\ir fn_validar_capas.sql

SELECT v.capa, v.filas, v.geom_nula, v.geom_vacia, v.srid_incorrecto, v.tipo_incorrecto,
       v.geom_invalida, v.campus_incorrecto, v.id_fuera_formato, v.ids_duplicados,
       CASE WHEN v.filas > 0
             AND v.geom_nula + v.geom_vacia + v.srid_incorrecto + v.tipo_incorrecto + v.geom_invalida
               + v.campus_incorrecto + v.id_fuera_formato + v.ids_duplicados = 0
            THEN 'OK' ELSE 'ERROR' END AS estado
FROM pg_temp.sigtec_validar(:'schema', :campus_id::smallint) AS v;
