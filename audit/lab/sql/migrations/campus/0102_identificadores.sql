-- =====================================================================
-- SIG-TEC · migración de campus 0102 — identificadores globales
--
--   id = campus_id × 1 000 000 000 + consecutivo_local
--
-- * Una sola secuencia por campus, compartida por las ocho tablas originales.
-- * Consecutivo 1..999 999 999, sin ciclo.
-- * El id se asigna al insertar cuando llega NULL u omitido (no hay DEFAULT
--   en id: así QGIS no consume consecutivos al abrir un formulario y las
--   cuentas de edición no necesitan permiso sobre la secuencia).
-- * Un id explícito se RECHAZA. Solo en modo de mantenimiento
--   (SET sigtec.permitir_id_explicito = on; p. ej. reincorporar objetos tras
--   una recuperación) se acepta si pertenece al campus, ya fue emitido por la
--   secuencia y no existe en ninguna de las ocho capas. Así un id nunca choca
--   con la secuencia ni se repite entre capas.
-- * id y campus_id son inmutables después de insertar.
--
-- Estas reglas solo existen en las tablas ORIGINALES del campus. Las copias
-- del nodo central (Integrante 2) reciben el id ya asignado por replicación.
--
-- Variables: :schema, :campus_id, :seq (nombre calificado de la secuencia)
-- =====================================================================

CREATE SEQUENCE :"schema".objeto_id_seq
    AS bigint MINVALUE 1 MAXVALUE 999999999 START WITH 1 INCREMENT BY 1 NO CYCLE;
COMMENT ON SEQUENCE :"schema".objeto_id_seq IS
  'Consecutivo local compartido por las ocho capas del campus (1..999 999 999).';
REVOKE ALL ON SEQUENCE :"schema".objeto_id_seq FROM PUBLIC;

-- ---------------------------------------------------------------------
-- BEFORE INSERT: asigna/valida campus_id e id
-- Argumentos: TG_ARGV[0] = campus_id del nodo, TG_ARGV[1] = secuencia
-- ---------------------------------------------------------------------
CREATE FUNCTION :"schema".tg_asignar_identificador()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
    v_campus  smallint := TG_ARGV[0]::smallint;
    v_seq     regclass := TG_ARGV[1]::regclass;
    v_base    bigint   := TG_ARGV[0]::bigint * 1000000000;
    v_ultimo  bigint;
    v_tabla   text;
    v_existe  boolean;
BEGIN
    IF NEW.campus_id IS NULL THEN
        NEW.campus_id := v_campus;
    ELSIF NEW.campus_id <> v_campus THEN
        RAISE EXCEPTION 'SIG-TEC: campus_id % no pertenece a este nodo (campus %)', NEW.campus_id, v_campus
            USING ERRCODE = 'check_violation',
                  HINT = 'Las tablas originales solo aceptan objetos del campus propietario.';
    END IF;

    IF NEW.id IS NULL THEN
        NEW.id := v_base + nextval(v_seq);
        RETURN NEW;
    END IF;

    IF coalesce(current_setting('sigtec.permitir_id_explicito', true), 'off') <> 'on' THEN
        RAISE EXCEPTION 'SIG-TEC: el identificador global lo asigna PostgreSQL (se recibió id %)', NEW.id
            USING ERRCODE = 'check_violation',
                  HINT = 'Omita la columna id o envíe NULL.';
    END IF;

    -- Modo de mantenimiento: id explícito ya emitido y libre en las ocho capas
    v_ultimo := coalesce(pg_sequence_last_value(v_seq), 0);
    IF NEW.id <= v_base OR NEW.id > v_base + v_ultimo THEN
        RAISE EXCEPTION 'SIG-TEC: id % no fue emitido por la secuencia del campus % (último consecutivo: %)',
                        NEW.id, v_campus, v_ultimo
            USING ERRCODE = 'check_violation',
                  HINT = 'Avance la secuencia con setval() antes de reinsertar identificadores posteriores.';
    END IF;
    FOREACH v_tabla IN ARRAY ARRAY['edificios','carreteras','aceras','parqueos','zonas_verdes',
                                   'puntos_interes','iluminacion','accesibilidad']
    LOOP
        EXECUTE format('SELECT EXISTS (SELECT 1 FROM %I.%I WHERE id = $1)', TG_TABLE_SCHEMA, v_tabla)
            INTO v_existe USING NEW.id;
        IF v_existe THEN
            RAISE EXCEPTION 'SIG-TEC: el id % ya existe en %.%', NEW.id, TG_TABLE_SCHEMA, v_tabla
                USING ERRCODE = 'unique_violation';
        END IF;
    END LOOP;
    RETURN NEW;
END
$fn$;
COMMENT ON FUNCTION :"schema".tg_asignar_identificador() IS
  'SIG-TEC: asigna id = campus_id*1e9 + nextval(secuencia local) y valida campus_id en INSERT. Rechaza id explícito salvo sigtec.permitir_id_explicito=on.';

-- ---------------------------------------------------------------------
-- BEFORE UPDATE: inmutabilidad de id y campus_id
-- ---------------------------------------------------------------------
CREATE FUNCTION :"schema".tg_proteger_identificador()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $fn$
BEGIN
    IF NEW.id IS DISTINCT FROM OLD.id THEN
        RAISE EXCEPTION 'SIG-TEC: el identificador global es inmutable (% -> %)', OLD.id, NEW.id
            USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.campus_id IS DISTINCT FROM OLD.campus_id THEN
        RAISE EXCEPTION 'SIG-TEC: el campus propietario es inmutable (objeto %: % -> %)', OLD.id, OLD.campus_id, NEW.campus_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END
$fn$;
COMMENT ON FUNCTION :"schema".tg_proteger_identificador() IS
  'SIG-TEC: impide cambiar id o campus_id de un objeto existente.';

REVOKE ALL ON FUNCTION :"schema".tg_asignar_identificador()  FROM PUBLIC;
REVOKE ALL ON FUNCTION :"schema".tg_proteger_identificador() FROM PUBLIC;

-- ---------------------------------------------------------------------
-- Disparadores en las ocho tablas
-- ---------------------------------------------------------------------
SELECT set_config('sigtec.schema', :'schema', true),
       set_config('sigtec.campus_id', :'campus_id', true),
       set_config('sigtec.seq', :'seq', true) AS _sigtec_seq \gset
DO $trg$
DECLARE
    s   text := current_setting('sigtec.schema');
    cid text := current_setting('sigtec.campus_id');
    sq  text := current_setting('sigtec.seq');
    t   text;
BEGIN
    FOREACH t IN ARRAY ARRAY['edificios','carreteras','aceras','parqueos','zonas_verdes',
                             'puntos_interes','iluminacion','accesibilidad']
    LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_10_asignar_identificador BEFORE INSERT ON %I.%I
                 FOR EACH ROW EXECUTE FUNCTION %I.tg_asignar_identificador(%L, %L)', s, t, s, cid, sq);
        EXECUTE format(
            'CREATE TRIGGER trg_20_proteger_identificador BEFORE UPDATE ON %I.%I
                 FOR EACH ROW EXECUTE FUNCTION %I.tg_proteger_identificador()', s, t, s);
    END LOOP;
END
$trg$;
