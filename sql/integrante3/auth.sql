-- SIG-TEC · Integrante 3 · catálogo central de autenticación
-- Se ejecuta únicamente en pg-central como administrador.
-- Las cuentas LOGIN y sus contraseñas se sincronizan desde
-- scripts/integrante3/manage.py; este archivo nunca contiene secretos.

BEGIN;

CREATE SCHEMA IF NOT EXISTS auth;
REVOKE ALL ON SCHEMA auth FROM PUBLIC;

CREATE TABLE IF NOT EXISTS auth.campus (
    campus_id smallint PRIMARY KEY CHECK (campus_id BETWEEN 1 AND 5),
    node_code text NOT NULL UNIQUE,
    campus_nombre text NOT NULL,
    activo boolean NOT NULL DEFAULT true
);

INSERT INTO auth.campus (campus_id, node_code, campus_nombre) VALUES
    (1, 'cartago',    'Campus Tecnológico Central, Cartago'),
    (2, 'san_jose',   'Campus Tecnológico Local San José'),
    (3, 'san_carlos', 'Campus Tecnológico Local San Carlos'),
    (4, 'alajuela',   'Campus Tecnológico Local Alajuela'),
    (5, 'limon',      'Campus Tecnológico Local Limón')
ON CONFLICT (campus_id) DO UPDATE
SET node_code = EXCLUDED.node_code,
    campus_nombre = EXCLUDED.campus_nombre;

CREATE TABLE IF NOT EXISTS auth.usuario_campus (
    usuario name PRIMARY KEY,
    campus_id smallint NOT NULL REFERENCES auth.campus(campus_id),
    activo boolean NOT NULL DEFAULT true,
    creado_en timestamptz NOT NULL DEFAULT clock_timestamp()
);

REVOKE ALL ON ALL TABLES IN SCHEMA auth FROM PUBLIC;

-- La contraseña ya fue validada por PostgreSQL al abrir la sesión. Esta función
-- SECURITY DEFINER revela únicamente la asignación de session_user y no acepta
-- un nombre de usuario suministrado por el cliente.
CREATE OR REPLACE FUNCTION auth.sesion_campus()
RETURNS TABLE(campus_id smallint, node_code text, campus_nombre text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, auth
AS $$
    SELECT c.campus_id, c.node_code, c.campus_nombre
      FROM auth.usuario_campus AS u
      JOIN auth.campus AS c USING (campus_id)
     WHERE u.usuario = session_user
       AND u.activo
       AND c.activo
$$;

REVOKE ALL ON FUNCTION auth.sesion_campus() FROM PUBLIC;

COMMENT ON SCHEMA auth IS
  'SIG-TEC: autenticación central y asignación inmutable de usuarios a campus.';
COMMENT ON FUNCTION auth.sesion_campus() IS
  'Devuelve el campus activo de la identidad PostgreSQL autenticada (session_user).';

COMMIT;
