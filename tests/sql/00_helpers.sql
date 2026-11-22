-- SIG-TEC · utilidades de prueba (funciones temporales de sesión)
-- Cada prueba devuelve una línea:  PASS|nombre|detalle   o   FAIL|nombre|detalle

CREATE OR REPLACE FUNCTION pg_temp.t(p_nombre text, p_ok boolean, p_detalle text DEFAULT '')
RETURNS text LANGUAGE sql AS $$
    SELECT CASE WHEN coalesce(p_ok, false) THEN 'PASS' ELSE 'FAIL' END || '|' || p_nombre || '|' || coalesce(p_detalle, 'NULL');
$$;

-- Ejecuta p_sql y devuelve 'NO_ERROR' o 'SQLSTATE: mensaje'. Sus efectos se revierten siempre.
CREATE OR REPLACE FUNCTION pg_temp.expect_error(p_sql text)
RETURNS text LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
        RAISE EXCEPTION USING ERRCODE = 'ZZ999', MESSAGE = '__NO_ERROR__';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = 'ZZ999' THEN RETURN 'NO_ERROR'; END IF;
        RETURN SQLSTATE || ': ' || SQLERRM;
    END;
END
$$;
