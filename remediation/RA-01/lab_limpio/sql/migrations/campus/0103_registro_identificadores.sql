-- =====================================================================
-- SIG-TEC · migración de campus 0103 — registro transaccional de
-- identificadores globales y autorización real del modo de mantenimiento
-- (corrección del hallazgo F-02 de la auditoría).
--
-- Problemas que corrige (verificados en laboratorio):
--   a) El modo de id explícito dependía solo de la variable de sesión
--      sigtec.permitir_id_explicito, que cualquier rol puede fijar, y la
--      función era SECURITY DEFINER: un rol sin privilegios insertaba ids.
--   b) La unicidad entre las ocho capas se comprobaba con SELECT EXISTS:
--      dos transacciones concurrentes no ven sus filas sin confirmar y cada
--      clave primaria es independiente; ambas confirmaban el mismo id.
--
-- Mecanismo definitivo:
--   * ops.identificadores_globales (id PRIMARY KEY): un id por objeto del
--     campus, sin importar la capa. Lo alimenta un disparador AFTER INSERT
--     (SECURITY DEFINER, no invocable ni reutilizable por otros roles) con
--     INSERT ... ON CONFLICT DO NOTHING. Ante una inserción concurrente del
--     mismo id, PostgreSQL espera a la otra transacción y, si confirma,
--     rechaza esta (23505). Las filas eliminadas conservan su registro: un
--     id nunca se reutiliza.
--   * tg_asignar_identificador pasa a SECURITY INVOKER: current_user es el
--     rol que realmente inserta (también tras SET ROLE). El id explícito
--     exige sigtec.permitir_id_explicito = on Y pertenecer al rol
--     sigtec_mantenimiento_id; además invoca una función cuyo EXECUTE solo
--     tiene ese rol (doble control con el sistema de privilegios).
--   * nextval y la lectura de la secuencia se hacen en funciones SECURITY
--     DEFINER mínimas: las cuentas de edición siguen sin privilegios sobre
--     la secuencia.
-- Migración NO destructiva: si existen ids repetidos entre capas, aborta sin
-- modificar nada e informa los conflictos (no borra ni renumera).
--
-- Variables: :schema, :campus_id, :seq
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Rol de grupo para mantenimiento de identificadores (sin LOGIN)
-- ---------------------------------------------------------------------
DO $rol$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sigtec_mantenimiento_id') THEN
        CREATE ROLE sigtec_mantenimiento_id NOLOGIN;
    END IF;
END
$rol$;
COMMENT ON ROLE sigtec_mantenimiento_id IS
  'SIG-TEC: autoriza insertar ids explícitos ya emitidos (reincorporación tras recuperación). Sin LOGIN; se otorga a operadores con GRANT.';

-- ---------------------------------------------------------------------
-- 2. Registro de identificadores
-- ---------------------------------------------------------------------
CREATE TABLE ops.identificadores_globales (
    id             bigint      NOT NULL,
    campus_id      smallint    NOT NULL,
    capa           text        NOT NULL,
    origen         text        NOT NULL,
    registrado_en  timestamptz NOT NULL DEFAULT clock_timestamp(),
    sesion         text        NOT NULL DEFAULT session_user,
    CONSTRAINT identificadores_globales_pkey PRIMARY KEY (id),
    CONSTRAINT identificadores_globales_campus_ck CHECK (campus_id = :campus_id),
    CONSTRAINT identificadores_globales_formato_ck
        CHECK (id BETWEEN campus_id::bigint * 1000000000 + 1 AND campus_id::bigint * 1000000000 + 999999999),
    CONSTRAINT identificadores_globales_capa_ck
        CHECK (capa IN ('edificios','carreteras','aceras','parqueos','zonas_verdes',
                        'puntos_interes','iluminacion','accesibilidad')),
    CONSTRAINT identificadores_globales_origen_ck CHECK (origen IN ('migracion_0103','insercion'))
);
COMMENT ON TABLE ops.identificadores_globales IS
  'SIG-TEC: identificadores globales emitidos en este campus (uno por objeto, en cualquiera de las ocho capas). La PK garantiza la unicidad entre capas bajo concurrencia. Las filas no se borran al eliminar el objeto: un id no se reutiliza. Esquema ops: no se publica.';
REVOKE ALL ON ops.identificadores_globales FROM PUBLIC;

-- ---------------------------------------------------------------------
-- 3. Comprobaciones previas y carga de los ids existentes
-- ---------------------------------------------------------------------
SELECT set_config('sigtec.schema', :'schema', true),
       set_config('sigtec.campus_id', :'campus_id', true),
       set_config('sigtec.seq', :'seq', true) AS _sigtec_vars \gset

DO $carga$
DECLARE
    s       text     := current_setting('sigtec.schema');
    cid     bigint   := current_setting('sigtec.campus_id')::bigint;
    sq      regclass := current_setting('sigtec.seq')::regclass;
    capas   text[]   := ARRAY['edificios','carreteras','aceras','parqueos','zonas_verdes',
                              'puntos_interes','iluminacion','accesibilidad'];
    u       text;
    v_n     bigint;
    v_dups  text;
    v_filas bigint;
    v_reg   bigint;
    v_max   bigint;
    v_last  bigint;
BEGIN
    SELECT string_agg(format('SELECT id, %L::text AS capa FROM %I.%I', c, s, c), ' UNION ALL ')
      INTO u FROM unnest(capas) AS c;

    -- a) ids repetidos entre capas: se informa y se aborta (nada queda aplicado)
    EXECUTE format('SELECT count(*), string_agg(id || '' en '' || capas, ''; '' ORDER BY id)
                      FROM (SELECT id, string_agg(capa, ''+'' ORDER BY capa) AS capas
                              FROM (%s) t GROUP BY id HAVING count(*) > 1) d', u)
       INTO v_n, v_dups;
    IF v_n > 0 THEN
        RAISE EXCEPTION 'SIG-TEC 0103: % identificador(es) repetido(s) entre capas de %: %', v_n, s, v_dups
            USING ERRCODE = 'unique_violation',
                  HINT = 'La migración no modificó nada. Decida qué objeto conserva cada id (ver docs/BACKUP_RECOVERY.md, "Conflictos de identificadores"), resuélvalo y repita make migrate.';
    END IF;

    -- b) consistencia con la secuencia: ningún id existente puede estar por
    --    encima del último consecutivo emitido (chocaría con nextval futuros)
    EXECUTE format('SELECT count(*), coalesce(max(id %% 1000000000), 0) FROM (%s) t', u) INTO v_filas, v_max;
    v_last := coalesce(pg_sequence_last_value(sq), 0);
    IF v_max > v_last THEN
        PERFORM setval(sq, v_max);
        RAISE NOTICE 'SIG-TEC 0103: la secuencia % estaba en % y existen consecutivos hasta %; se adelantó a % (no se modificó ningún dato)',
                     sq, v_last, v_max, v_max;
    END IF;

    -- c) registro de los ids existentes
    EXECUTE format('INSERT INTO ops.identificadores_globales (id, campus_id, capa, origen, sesion)
                    SELECT id, %s, capa, ''migracion_0103'', session_user FROM (%s) t', cid, u);
    SELECT count(*) INTO v_reg FROM ops.identificadores_globales;
    IF v_reg <> v_filas THEN
        RAISE EXCEPTION 'SIG-TEC 0103: se registraron % ids pero existen % objetos', v_reg, v_filas;
    END IF;
    RAISE NOTICE 'SIG-TEC 0103: % identificadores existentes registrados en ops.identificadores_globales', v_reg;
END
$carga$;

-- ---------------------------------------------------------------------
-- 4. Funciones auxiliares (SECURITY DEFINER mínimas) y disparadores
-- ---------------------------------------------------------------------
DO $fn$
DECLARE
    s    text   := current_setting('sigtec.schema');
    cid  bigint := current_setting('sigtec.campus_id')::bigint;
    sq   text   := current_setting('sigtec.seq');
    t    text;
BEGIN
    -- 4.1 siguiente id del campus (nextval sin dar privilegios de secuencia)
    EXECUTE format($f$
        CREATE FUNCTION %1$I.sigtec_id_siguiente()
        RETURNS bigint LANGUAGE sql VOLATILE SECURITY DEFINER
        SET search_path = pg_catalog, pg_temp
        AS $s$SELECT %2$s::bigint * 1000000000 + nextval(%3$L::regclass)$s$
    $f$, s, cid, sq);
    EXECUTE format('COMMENT ON FUNCTION %I.sigtec_id_siguiente() IS %L', s,
        'SIG-TEC: id = campus_id*1e9 + nextval(secuencia del campus). Lo usa el disparador de asignación.');
    EXECUTE format('REVOKE ALL ON FUNCTION %I.sigtec_id_siguiente() FROM PUBLIC', s);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %I.sigtec_id_siguiente() TO PUBLIC', s);

    -- 4.2 autorización de un id explícito: SOLO el rol de mantenimiento
    EXECUTE format($f$
        CREATE FUNCTION %1$I.sigtec_id_autorizar_explicito(p_id bigint)
        RETURNS void LANGUAGE plpgsql SECURITY DEFINER
        SET search_path = pg_catalog, pg_temp
        AS $b$
        DECLARE
            v_base  bigint := %2$s::bigint * 1000000000;
            v_last  bigint := coalesce(pg_sequence_last_value(%3$L::regclass), 0);
        BEGIN
            IF p_id IS NULL OR p_id <= v_base OR p_id > v_base + v_last THEN
                RAISE EXCEPTION 'SIG-TEC: id %% no fue emitido por la secuencia del campus %2$s (último consecutivo: %%)', p_id, v_last
                    USING ERRCODE = 'check_violation',
                          HINT = 'Avance la secuencia con setval() antes de reinsertar identificadores posteriores.';
            END IF;
        END
        $b$
    $f$, s, cid, sq);
    EXECUTE format('COMMENT ON FUNCTION %I.sigtec_id_autorizar_explicito(bigint) IS %L', s,
        'SIG-TEC: valida un id explícito (ya emitido por la secuencia). EXECUTE solo para sigtec_mantenimiento_id.');
    EXECUTE format('REVOKE ALL ON FUNCTION %I.sigtec_id_autorizar_explicito(bigint) FROM PUBLIC', s);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %I.sigtec_id_autorizar_explicito(bigint) TO sigtec_mantenimiento_id', s);

    -- 4.3 disparador BEFORE INSERT, ahora SECURITY INVOKER
    EXECUTE format($f$
        CREATE OR REPLACE FUNCTION %1$I.tg_asignar_identificador()
        RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
        SET search_path = pg_catalog, pg_temp
        AS $b$
        DECLARE
            v_campus smallint := TG_ARGV[0]::smallint;
        BEGIN
            IF NEW.campus_id IS NULL THEN
                NEW.campus_id := v_campus;
            ELSIF NEW.campus_id <> v_campus THEN
                RAISE EXCEPTION 'SIG-TEC: campus_id %% no pertenece a este nodo (campus %%)', NEW.campus_id, v_campus
                    USING ERRCODE = 'check_violation',
                          HINT = 'Las tablas originales solo aceptan objetos del campus propietario.';
            END IF;

            IF NEW.id IS NULL THEN
                NEW.id := %1$I.sigtec_id_siguiente();
                RETURN NEW;
            END IF;

            IF coalesce(current_setting('sigtec.permitir_id_explicito', true), 'off') <> 'on' THEN
                RAISE EXCEPTION 'SIG-TEC: el identificador global lo asigna PostgreSQL (se recibió id %%)', NEW.id
                    USING ERRCODE = 'check_violation',
                          HINT = 'Omita la columna id o envíe NULL.';
            END IF;
            -- current_user es el rol que inserta (función SECURITY INVOKER)
            IF NOT pg_has_role(current_user, 'sigtec_mantenimiento_id', 'USAGE') THEN
                RAISE EXCEPTION 'SIG-TEC: el rol %% no está autorizado para insertar identificadores explícitos', current_user
                    USING ERRCODE = 'insufficient_privilege',
                          HINT = 'Solo los miembros de sigtec_mantenimiento_id pueden usar sigtec.permitir_id_explicito.';
            END IF;
            PERFORM %1$I.sigtec_id_autorizar_explicito(NEW.id);
            -- La unicidad entre capas la garantiza ops.identificadores_globales (disparador AFTER).
            RETURN NEW;
        END
        $b$
    $f$, s);
    EXECUTE format('COMMENT ON FUNCTION %I.tg_asignar_identificador() IS %L', s,
        'SIG-TEC: asigna id = campus_id*1e9 + nextval en INSERT y valida campus_id. Id explícito solo con sigtec.permitir_id_explicito=on y rol sigtec_mantenimiento_id (SECURITY INVOKER).');

    -- 4.4 disparador AFTER INSERT: reserva atómica en el registro
    EXECUTE format($f$
        CREATE FUNCTION %1$I.tg_registrar_identificador()
        RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
        SET search_path = pg_catalog, pg_temp
        AS $b$
        DECLARE
            v_capa text;
        BEGIN
            INSERT INTO ops.identificadores_globales (id, campus_id, capa, origen, sesion)
            VALUES (NEW.id, NEW.campus_id, TG_TABLE_NAME, 'insercion', session_user)
            ON CONFLICT (id) DO NOTHING;
            IF NOT FOUND THEN
                SELECT capa INTO v_capa FROM ops.identificadores_globales WHERE id = NEW.id;
                RAISE EXCEPTION 'SIG-TEC: el id %% ya existe en el registro global del campus (asignado en %%; los ids eliminados tampoco se reutilizan)', NEW.id, v_capa
                    USING ERRCODE = 'unique_violation',
                          HINT = 'Omita la columna id para que PostgreSQL asigne uno nuevo.';
            END IF;
            RETURN NULL;
        END
        $b$
    $f$, s);
    EXECUTE format('COMMENT ON FUNCTION %I.tg_registrar_identificador() IS %L', s,
        'SIG-TEC: registra cada id en ops.identificadores_globales (PK) dentro de la misma transacción; rechaza ids ya registrados.');
    EXECUTE format('REVOKE ALL ON FUNCTION %I.tg_registrar_identificador() FROM PUBLIC', s);

    FOREACH t IN ARRAY ARRAY['edificios','carreteras','aceras','parqueos','zonas_verdes',
                             'puntos_interes','iluminacion','accesibilidad']
    LOOP
        EXECUTE format('CREATE TRIGGER trg_30_registrar_identificador AFTER INSERT ON %I.%I
                            FOR EACH ROW EXECUTE FUNCTION %I.tg_registrar_identificador()', s, t, s);
    END LOOP;

    -- 4.5 privilegios explícitos del rol de mantenimiento (sin UPDATE/DELETE)
    EXECUTE format('GRANT USAGE ON SCHEMA %I TO sigtec_mantenimiento_id', s);
    EXECUTE format('GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA %I TO sigtec_mantenimiento_id', s);
END
$fn$;
