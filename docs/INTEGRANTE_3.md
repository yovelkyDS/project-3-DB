# Integrante 3 · autenticación, complemento PyQGIS y estilos

## Resultado entregado

Este bloque completa las cinco responsabilidades asignadas al integrante 3:

1. autenticación PostgreSQL en el nodo central y asociación de una cuenta a cada campus;
2. complemento instalable **SIG-TEC** para QGIS 3.44 LTR;
3. carga automática e idempotente de las ocho vistas `qgis.v_*` con `id`, `geom` y EPSG:5367;
4. ocho estilos institucionales guardados en `public.layer_styles`, distribuidos a los campus y acompañados por un respaldo local;
5. verificación automatizada, manual de usuario y guion de demostración.

La contraseña no se compara en código ni se guarda en tablas. PostgreSQL valida la conexión mediante SCRAM-SHA-256 y `auth.sesion_campus()` resuelve únicamente la asignación de `session_user`. El complemento guarda las credenciales en el almacén cifrado de autenticación de QGIS y las capas conservan solo su `authcfg`.

## Instalación completa

Requisitos: Docker activo, Python 3.10 o posterior y QGIS Desktop 3.44 LTR. Desde la raíz del repositorio:

```bash
make setup
make replication-setup
make integrante3-setup
```

En Windows se pueden ejecutar los equivalentes directamente:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
python scripts\distributed\manage.py setup
python scripts\integrante3\manage.py setup
```

El último comando es idempotente: sincroniza las cuentas y asignaciones, vuelve a publicar los estilos, ejecuta la verificación y genera `dist/sigtec_qgis.zip`. No muestra ninguna contraseña. Si el integrante 2 todavía no creó las vistas y cuentas de datos, se detiene con una instrucción explícita.

## Instalar el complemento en QGIS

1. Abrir QGIS 3.44 LTR con un perfil limpio.
2. Ir a **Complementos > Administrar e instalar complementos > Instalar a partir de ZIP**.
3. Seleccionar `dist/sigtec_qgis.zip` y aceptar la advertencia de instalación local.
4. Activar **SIG-TEC** si QGIS no lo activa automáticamente.
5. Configurar o desbloquear la contraseña maestra cuando QGIS lo solicite. Esto protege el almacén local de credenciales.
6. Usar el botón **Iniciar sesión en SIG-TEC** o el menú **Base de datos > SIG-TEC**.

Las cuentas son `qgis_cartago`, `qgis_san_jose`, `qgis_san_carlos`, `qgis_alajuela` y `qgis_limon`. Sus contraseñas distintas están en el `.env` local bajo `SIGTEC_QGIS_<CAMPUS>_PASSWORD`; no deben copiarse a documentación, capturas ni control de versiones.

## Configuración de conexiones

El archivo `qgis_plugin/sigtec/config.json` usa `127.0.0.1` y los puertos contractuales 55430–55435. Al ejecutar `make qgis-plugin` o `manage.py package`, el ZIP toma automáticamente los puertos efectivos de `.env`; esto cubre los rangos que Windows/Hyper-V pueda reservar sin modificar el archivo versionado. Si QGIS corre en otra máquina, cambie únicamente los hosts y asegure la red. Se exige TLS (`sslmode=require`) y un tiempo máximo de conexión de cinco segundos.

Para comprobar una instancia recuperada de San Carlos ya reincorporada por el integrante 2, detener el dueño anterior y cambiar temporalmente el puerto de `san_carlos` a `55436`; luego ejecutar `make qgis-plugin` e instalar nuevamente el ZIP.

## Uso diario

Después de una sesión correcta aparece un grupo **SIG-TEC** con:

| Vista | Nombre en QGIS | Geometría |
|---|---|---|
| `qgis.v_edificios` | Edificios | Polygon |
| `qgis.v_carreteras` | Carreteras | LineString |
| `qgis.v_aceras` | Aceras | LineString |
| `qgis.v_parqueos` | Parqueos | Polygon |
| `qgis.v_zonas_verdes` | Zonas verdes | Polygon |
| `qgis.v_puntos_interes` | Puntos de interés | Point |
| `qgis.v_iluminacion` | Iluminación | Point |
| `qgis.v_accesibilidad` | Accesibilidad | LineString |

Cada capa usa `id` como clave, `geom` como geometría y EPSG:5367. Todas contienen información de los cinco campus. Al iniciar sesión, el mapa se centra en los objetos del campus de la cuenta. Un nuevo inicio de sesión elimina solo las capas administradas previamente por el complemento y coloca las ocho nuevas, por lo que nunca se duplican ni se borran capas ajenas del proyecto.

### Editar datos propios

1. Activar edición en una capa y crear un objeto dentro del campus.
2. Dejar `id` y `campus_id` vacíos: PostgreSQL los asigna.
3. Completar los atributos obligatorios y guardar.
4. Modificar el objeto y guardar; luego eliminarlo y guardar de nuevo.

Los disparadores `INSTEAD OF` del integrante 2 enrutan el cambio a la tabla original. Un objeto ajeno se puede consultar, pero su actualización o eliminación devuelve “No se permite editar un campus ajeno” y no altera PostgreSQL. Tampoco se permite cambiar `id` o `campus_id`.

## Estilos institucionales

La fuente versionada está en `qgis_plugin/sigtec/styles/`. `make integrante3-setup` inserta esos ocho QML como estilos por defecto en el central y activa la publicación lógica `sigtec_styles`. El complemento intenta primero el estilo distribuido de la base y usa el QML local solo si todavía no llegó la réplica.

Para cambiar un estilo, editar el QML correspondiente y repetir:

```bash
make integrante3-setup
```

Después, abrir la misma capa con dos cuentas de campus y comprobar la misma simbología. `make integrante3-verify` exige exactamente ocho estilos predeterminados en cada nodo.

## Mensajes y solución de errores

| Mensaje | Causa y acción |
|---|---|
| No se pudo autenticar contra el nodo central | Usuario/clave incorrectos, central detenido o `config.json` equivocado. Revisar `docker compose ps` sin compartir secretos. |
| La cuenta no tiene un campus activo asignado | Revisar `auth.usuario_campus` y ejecutar `make integrante3-setup`. |
| El nodo `<campus>` no está accesible | Iniciar ese contenedor, corregir host/puerto o terminar la reincorporación. No se agrega un conjunto parcial de capas. |
| La vista `qgis.v_*` no existe | Ejecutar `make replication-setup` y después `make integrante3-setup`. |
| QGIS no pudo guardar las credenciales | Crear/desbloquear la contraseña maestra en **Preferencias > Opciones > Autenticación**. |
| No se permite editar un campus ajeno | Comportamiento esperado; cancelar la edición de ese objeto. |

## Pruebas y evidencia

Pruebas locales, sin QGIS ni Docker:

```bash
make integrante3-unit
make qgis-plugin
```

Prueba de integración con los seis nodos activos:

```bash
make integrante3-verify
```

La verificación inicia sesión con las cinco cuentas, comprueba la asignación de campus, exige que una clave incorrecta sea rechazada, revisa las 40 exposiciones de vistas (8 × 5) y espera los ocho estilos en cada nodo. La indisponibilidad se demuestra de forma segura deteniendo un campus, intentando iniciar sesión y volviéndolo a iniciar:

```bash
docker compose stop pg-san-carlos
# Intentar qgis_san_carlos: debe aparecer el mensaje de nodo inaccesible.
docker compose start pg-san-carlos
```

Para la evidencia visual se deben capturar: el formulario, las ocho capas sin duplicados, simbología igual en dos campus, CRUD propio, rechazo de CRUD ajeno y una sesión correcta contra el nodo recuperado.

## Guion del segmento del integrante 3 (aprox. 3 minutos)

1. Mostrar `make integrante3-verify` exitoso y explicar la autenticación central (20 s).
2. Instalar el ZIP en un perfil limpio e iniciar con `qgis_san_carlos` (30 s).
3. Mostrar las ocho capas, objetos de cinco campus y estilos (30 s).
4. Crear/modificar/eliminar un objeto propio y mostrar propagación (45 s).
5. Intentar editar uno ajeno y mostrar que PostgreSQL quedó intacto (30 s).
6. Mostrar error de contraseña y nodo inaccesible (25 s).
7. Conectar al puerto 55436 restaurado, recargar capas y editar un objeto permitido (30 s).

Al ensamblar el video total, conservar los segmentos de arquitectura/recuperación del integrante 1 y replicación/transacción del integrante 2; el proyecto completo no debe exceder diez minutos.

## Referencias técnicas

* QGIS 3.44, [Infraestructura de autenticación para PyQGIS](https://docs.qgis.org/3.44/en/docs/pyqgis_developer_cookbook/authentication.html): `QgsAuthManager`, configuraciones `Basic` y uso de `authcfg` con PostgreSQL.
* QGIS 3.44, [API de `QgsDataSourceUri`](https://api.qgis.org/api/3.44/classQgsDataSourceUri.html): conexión, SSL, esquema, tabla, geometría y clave.
* QGIS 3.44, [implementación oficial del proveedor PostgreSQL](https://github.com/qgis/QGIS/blob/release-3_44/src/providers/postgres/qgspostgresutils.cpp): firma de `public.layer_styles`.
* PostgreSQL 17, [autenticación por contraseña](https://www.postgresql.org/docs/17/auth-password.html): SCRAM-SHA-256 y administración de contraseñas de roles.
* PostgreSQL 17, [atributos de roles](https://www.postgresql.org/docs/17/role-attributes.html): `LOGIN` y principio de privilegios mínimos.
