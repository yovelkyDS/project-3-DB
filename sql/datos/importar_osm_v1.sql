-- =====================================================================
-- SIG-TEC · importa un campus real (OpenStreetMap) desde la tabla _entrada
-- Lo ejecuta scripts/datos/importar.py dentro de UNA transacción por campus.
--
-- * Transformación del enunciado: EPSG:4326 -> ST_SetSRID -> ST_Transform 5367.
-- * El id NO se envía: lo asigna el disparador (id global, nunca reutilizado).
-- * Los objetos sintéticos del seed se archivan en ops.datos_retirados antes de
--   retirarse; ningún otro objeto del campus se modifica.
-- * Los valores supuestos de cada objeto quedan en ops.procedencia_objetos.
-- Parámetros (set_config local): sigtec.imp_schema, imp_campus, imp_prefijo,
--   imp_margen y imp_entorno (metros).
-- =====================================================================
CREATE TABLE IF NOT EXISTS ops.procedencia_objetos (
    id              bigint PRIMARY KEY,
    capa            text NOT NULL,
    fuente          text NOT NULL CHECK (fuente IN ('osm', 'sintetico')),
    osm             text,
    osm_version     integer,
    osm_fecha       timestamptz,
    supuestos       text[] NOT NULL DEFAULT '{}',
    importado_en    timestamptz NOT NULL DEFAULT clock_timestamp()
);
COMMENT ON TABLE ops.procedencia_objetos IS
  'Origen de cada objeto importado (OpenStreetMap, ODbL 1.0, o demostración sintética) y sus atributos supuestos. No replicar.';
CREATE TABLE IF NOT EXISTS ops.datos_retirados (
    id           bigint NOT NULL,
    capa         text NOT NULL,
    fila         jsonb NOT NULL,
    motivo       text NOT NULL,
    retirado_en  timestamptz NOT NULL DEFAULT clock_timestamp()
);
COMMENT ON TABLE ops.datos_retirados IS
  'Copia íntegra (geom en EWKB hexadecimal) de los objetos sintéticos sustituidos por datos reales. No replicar.';
REVOKE ALL ON ops.procedencia_objetos, ops.datos_retirados FROM PUBLIC;

DO $$
DECLARE
    s        text := current_setting('sigtec.imp_schema');
    base     bigint := current_setting('sigtec.imp_campus')::bigint * 1000000000;
    prefijo  text := current_setting('sigtec.imp_prefijo');
    margen   float8 := current_setting('sigtec.imp_margen')::float8;
    entorno  float8 := current_setting('sigtec.imp_entorno')::float8;
    tope     bigint := (SELECT filas FROM ops.seed_runs WHERE seed_name = 'datos_sinteticos_v1');
    capas    text[] := ARRAY['edificios','carreteras','aceras','parqueos','zonas_verdes','puntos_interes','iluminacion','accesibilidad'];
    c        text;
    limite   geometry;
    vias     geometry;    -- recorte de carreteras
    cerca    geometry;    -- recinto donde se apoya la demostración
    ambito   geometry;    -- recorte de aceras, accesibilidad y zonas verdes
    f        record;
    g        geometry;
    nid      bigint;
    cap      integer;
    total    integer := 0;
    retirados integer := 0;
    n        integer;
BEGIN
    EXECUTE format('SET LOCAL search_path = %I, public, pg_temp', s);

    -- 1. Archivo y retiro del juego sintético (consecutivos 1..filas del seed)
    IF tope IS NOT NULL THEN
        FOREACH c IN ARRAY capas LOOP
            EXECUTE format($q$WITH r AS (DELETE FROM %I.%I t WHERE id BETWEEN $1 + 1 AND $1 + $2 RETURNING t.*)
                INSERT INTO ops.datos_retirados (id, capa, fila, motivo)
                SELECT id, %L, to_jsonb(r) || jsonb_build_object('geom', encode(ST_AsEWKB(geom), 'hex')),
                       'sustituido por datos_osm_v1' FROM r$q$, s, c, c) USING base, tope;
            GET DIAGNOSTICS n = ROW_COUNT;
            retirados := retirados + n;
        END LOOP;
    END IF;

    -- 2. Ámbitos de recorte, en metros (EPSG:5367)
    SELECT ST_Transform(ST_SetSRID(ST_GeomFromGeoJSON(doc->'limite'), 4326), 5367) INTO STRICT limite
    FROM _entrada WHERE doc ? 'limite';
    SELECT ST_Union(ST_Buffer(limite, margen), ST_Union(ST_Buffer(ST_Transform(ST_SetSRID(ST_GeomFromGeoJSON(doc->'geometry'), 4326), 5367), margen)))
      INTO vias FROM _entrada WHERE doc #>> '{properties,capa}' = 'edificios';
    cerca := ST_Buffer(limite, 20);
    ambito := ST_Buffer(limite, greatest(margen, entorno));
    vias := CASE WHEN entorno > 0 THEN ST_Union(vias, ambito) ELSE vias END;

    -- 3. Objetos reales
    FOR f IN SELECT doc->'properties' AS p, doc #> '{properties,atributos}' AS a,
                    ST_Transform(ST_SetSRID(ST_GeomFromGeoJSON(doc->'geometry'), 4326), 5367) AS geom,
                    ARRAY(SELECT jsonb_array_elements_text(doc #> '{properties,supuestos}')) AS sup, orden
             FROM _entrada WHERE doc ? 'geometry' ORDER BY orden
    LOOP
        c := f.p->>'capa';
        g := f.geom;
        IF c IN ('edificios','parqueos') THEN
            g := ST_CollectionExtract(ST_MakeValid(g), 3);
        ELSIF c = 'zonas_verdes' THEN
            g := ST_CollectionExtract(ST_Intersection(ST_MakeValid(g), ambito), 3);
        ELSIF c = 'carreteras' THEN
            g := ST_CollectionExtract(ST_Intersection(g, vias), 2);
        ELSIF c IN ('aceras','accesibilidad') THEN
            g := ST_CollectionExtract(ST_Intersection(g, ambito), 2);
        END IF;
        -- El modelo usa geometrías simples: una fila por parte con tamaño útil.
        FOR g IN SELECT d.geom FROM ST_Dump(g) d
                 WHERE CASE ST_Dimension(d.geom) WHEN 2 THEN ST_Area(d.geom) >= 4
                            WHEN 1 THEN ST_Length(d.geom) >= 2 ELSE true END
                 ORDER BY d.path
        LOOP
            IF c = 'edificios' THEN
                INSERT INTO edificios (nombre, codigo, area, pisos, geom)
                VALUES (f.a->>'nombre', f.a->>'codigo', round(ST_Area(g)::numeric, 2), (f.a->>'pisos')::int, g)
                ON CONFLICT (codigo) DO NOTHING RETURNING id INTO nid;
                CONTINUE WHEN nid IS NULL;
            ELSIF c = 'carreteras' THEN
                INSERT INTO carreteras (nombre, tipo, superficie, geom)
                VALUES (f.a->>'nombre', f.a->>'tipo', f.a->>'superficie', g) RETURNING id INTO nid;
            ELSIF c = 'aceras' THEN
                INSERT INTO aceras (material, ancho, condicion, geom)
                VALUES (f.a->>'material', (f.a->>'ancho')::numeric, f.a->>'condicion', g) RETURNING id INTO nid;
            ELSIF c = 'parqueos' THEN
                cap := coalesce((f.a->>'capacidad')::int,
                                greatest(1, round(ST_Area(g) / CASE f.a->>'tipo' WHEN 'bicicletas' THEN 1.5 WHEN 'motocicletas' THEN 3 ELSE 25 END)::int));
                INSERT INTO parqueos (capacidad, tipo, disponibilidad, geom)
                VALUES (cap, f.a->>'tipo', cap, g) RETURNING id INTO nid;
            ELSIF c = 'zonas_verdes' THEN
                INSERT INTO zonas_verdes (area, tipo_vegetacion, geom)
                VALUES (round(ST_Area(g)::numeric, 2), f.a->>'tipo_vegetacion', g) RETURNING id INTO nid;
            ELSIF c = 'puntos_interes' THEN
                INSERT INTO puntos_interes (nombre, tipo, descripcion, geom)
                VALUES (f.a->>'nombre', f.a->>'tipo', f.a->>'descripcion', g) RETURNING id INTO nid;
            ELSIF c = 'accesibilidad' THEN
                INSERT INTO accesibilidad (tipo, condicion, descripcion, geom)
                VALUES (f.a->>'tipo', f.a->>'condicion', f.a->>'descripcion', g) RETURNING id INTO nid;
            ELSE
                RAISE EXCEPTION 'capa no admitida: %', c;
            END IF;
            INSERT INTO ops.procedencia_objetos (id, capa, fuente, osm, osm_version, osm_fecha, supuestos)
            VALUES (nid, c, 'osm', f.p->>'osm', (f.p->>'osm_version')::int, (f.p->>'osm_fecha')::timestamptz, f.sup);
            total := total + 1;
        END LOOP;
    END LOOP;

    -- 4. Demostración sintética: OSM no registra luminarias ni casi accesibilidad.
    --    Se apoya en recorridos reales; el código y la descripción la identifican.
    n := 0;
    FOR g IN
        WITH r AS (   -- recorridos reales dentro del campus, aceras primero
            SELECT 1 AS pr, id, ST_Intersection(geom, cerca) AS geom FROM aceras WHERE ST_Intersects(geom, cerca)
            UNION ALL
            SELECT 2, id, ST_Intersection(geom, cerca) FROM carreteras WHERE ST_Intersects(geom, cerca)),
        l AS (SELECT pr, id, d.geom, ST_Length(d.geom) AS m FROM r, ST_Dump(ST_CollectionExtract(r.geom, 2)) d),
        p AS (SELECT pr, id, k, ST_LineInterpolatePoint(geom, least(1, k * 45.0 / m)) AS geom
              FROM l CROSS JOIN LATERAL generate_series(0, floor(m / 45.0)::int) k WHERE m > 10)
        SELECT geom FROM p ORDER BY pr, id, k
    LOOP
        CONTINUE WHEN EXISTS (SELECT 1 FROM iluminacion WHERE ST_DWithin(iluminacion.geom, g, 35));
        n := n + 1;
        EXIT WHEN n > 250;
        INSERT INTO iluminacion (codigo, potencia, estado, geom)
        VALUES ('SINT-' || prefijo || '-L' || lpad(n::text, 3, '0'), 100, 'funcional', g) RETURNING id INTO nid;
        INSERT INTO ops.procedencia_objetos (id, capa, fuente, supuestos)
        VALUES (nid, 'iluminacion', 'sintetico', '{codigo,potencia,estado,geom}');
        total := total + 1;
    END LOOP;

    n := 0;
    FOR g IN
        WITH r AS (
            SELECT 1 AS pr, ST_Intersection(geom, cerca) AS geom FROM aceras WHERE ST_Intersects(geom, cerca)
            UNION ALL SELECT 2, ST_Intersection(geom, cerca) FROM carreteras WHERE ST_Intersects(geom, cerca)
)
        SELECT ST_LineSubstring(d.geom, 0, least(1, CASE pr WHEN 1 THEN 60 ELSE 12 END / ST_Length(d.geom)))
        FROM r, ST_Dump(ST_CollectionExtract(r.geom, 2)) d WHERE ST_Length(d.geom) > 8
        ORDER BY pr, ST_Length(d.geom) DESC, ST_AsEWKB(d.geom) LIMIT 4
    LOOP
        n := n + 1;
        INSERT INTO accesibilidad (tipo, condicion, descripcion, geom)
        VALUES ('ruta_accesible', 'regular',
                'DATO SINTÉTICO de demostración sobre un recorrido real; no certifica accesibilidad.', g)
        RETURNING id INTO nid;
        INSERT INTO ops.procedencia_objetos (id, capa, fuente, supuestos)
        VALUES (nid, 'accesibilidad', 'sintetico', '{tipo,condicion,descripcion,geom}');
        total := total + 1;
    END LOOP;

    INSERT INTO ops.seed_runs (seed_name, filas, descripcion)
    VALUES ('datos_osm_v1', total,
            'Geografía real © colaboradores de OpenStreetMap (ODbL 1.0). Iluminación y accesibilidad marcadas SINT/SINTÉTICO son demostración. Detalle por objeto en ops.procedencia_objetos. Sintéticos retirados: ' || retirados || ' (archivo en ops.datos_retirados).');
END $$;
