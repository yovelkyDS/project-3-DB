-- Aplicar en todos los nodos como postgres antes de las suscripciones.
CREATE SCHEMA IF NOT EXISTS global;
CREATE SCHEMA IF NOT EXISTS qgis;
REVOKE ALL ON SCHEMA global, qgis FROM PUBLIC;
CREATE TABLE IF NOT EXISTS ops.editor_campus (
    usuario name PRIMARY KEY, campus_id smallint NOT NULL CHECK(campus_id BETWEEN 1 AND 5)
);
REVOKE ALL ON ops.editor_campus FROM PUBLIC;
CREATE TABLE IF NOT EXISTS ops.operaciones_distribuidas (
    id text PRIMARY KEY, detalle text NOT NULL, creado_en timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON ops.operaciones_distribuidas FROM PUBLIC;

CREATE TABLE IF NOT EXISTS ops.replication_highwater (campus_id smallint PRIMARY KEY, id bigint NOT NULL);
REVOKE ALL ON ops.replication_highwater FROM PUBLIC;

CREATE OR REPLACE FUNCTION ops.consolidar_capa() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE cols text; vals text; updates text;
BEGIN
    INSERT INTO ops.replication_highwater VALUES (CASE WHEN TG_OP='DELETE' THEN OLD.campus_id ELSE NEW.campus_id END, CASE WHEN TG_OP='DELETE' THEN OLD.id ELSE NEW.id END)
    ON CONFLICT(campus_id) DO UPDATE SET id=greatest(ops.replication_highwater.id,EXCLUDED.id);
    IF TG_OP = 'DELETE' THEN
        EXECUTE format('DELETE FROM global.%I WHERE id=$1', TG_TABLE_NAME) USING OLD.id;
        RETURN OLD;
    END IF;
    SELECT string_agg(format('%I',attname),',' ORDER BY attnum),
           string_agg(format('($1).%I',attname),',' ORDER BY attnum),
           string_agg(format('%1$I=EXCLUDED.%1$I',attname),',' ORDER BY attnum)
      INTO cols, vals, updates FROM pg_attribute
      WHERE attrelid=TG_RELID AND attnum>0 AND NOT attisdropped;
    EXECUTE format('INSERT INTO global.%I (%s) SELECT %s ON CONFLICT(id) DO UPDATE SET %s',
                   TG_TABLE_NAME,cols,vals,updates) USING NEW;
    RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION ops.consolidar_capa() FROM PUBLIC;

CREATE OR REPLACE FUNCTION ops.editar_capa() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE n record; permitido smallint; cols text; vals text; changes text; found_id bigint;
BEGIN
    SELECT * INTO STRICT n FROM ops.node_info WHERE singleton;
    SELECT campus_id INTO permitido FROM ops.editor_campus WHERE usuario=session_user;
    IF permitido IS NULL OR permitido IS DISTINCT FROM n.campus_id THEN
        RAISE EXCEPTION 'Identidad no autorizada para este campus' USING ERRCODE='42501';
    END IF;
    IF TG_OP <> 'INSERT' THEN
        IF OLD.campus_id IS DISTINCT FROM permitido THEN
            RAISE EXCEPTION 'No se permite editar un campus ajeno' USING ERRCODE='42501';
        END IF;
        EXECUTE format('SELECT id FROM %I.%I WHERE id=$1 AND campus_id=$2 FOR UPDATE',
                       n.local_schema,TG_ARGV[0]) INTO found_id USING OLD.id,permitido;
        IF found_id IS NULL THEN RETURN NULL; END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN
        EXECUTE format('DELETE FROM %I.%I WHERE id=$1',n.local_schema,TG_ARGV[0]) USING OLD.id;
        RETURN OLD;
    END IF;
    IF TG_OP = 'UPDATE' AND (NEW.id IS DISTINCT FROM OLD.id OR NEW.campus_id IS DISTINCT FROM OLD.campus_id) THEN
        RAISE EXCEPTION 'id y campus_id son inmutables' USING ERRCODE='23514';
    END IF;
    IF TG_OP = 'INSERT' THEN
        IF NEW.id IS NOT NULL OR (NEW.campus_id IS NOT NULL AND NEW.campus_id <> permitido) THEN
            RAISE EXCEPTION 'Alta sin id y solamente en el campus propio' USING ERRCODE='23514';
        END IF;
        NEW.campus_id := permitido;
    END IF;
    SELECT string_agg(format('%I',attname),',' ORDER BY attnum),
           string_agg(format('($1).%I',attname),',' ORDER BY attnum),
           string_agg(format('%1$I=($1).%1$I',attname),',' ORDER BY attnum)
    INTO cols, vals, changes FROM pg_attribute
    WHERE attrelid=format('%I.%I',n.local_schema,TG_ARGV[0])::regclass
      AND attnum>0 AND NOT attisdropped AND attname NOT IN ('id','campus_id');
    IF TG_OP = 'INSERT' THEN
        EXECUTE format('INSERT INTO %I.%I (%s,campus_id) SELECT %s,($1).campus_id RETURNING *',
                       n.local_schema,TG_ARGV[0],cols,vals) INTO NEW USING NEW;
    ELSE
        EXECUTE format('UPDATE %I.%I SET %s WHERE id=$2 RETURNING *',
                       n.local_schema,TG_ARGV[0],changes) INTO NEW USING NEW,OLD.id;
    END IF;
    RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION ops.editar_capa() FROM PUBLIC;
