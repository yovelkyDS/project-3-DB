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
make datos-reales
make integrante3-setup
```

En Windows se pueden ejecutar los equivalentes directamente:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
python scripts\distributed\manage.py setup
python scripts\datos\importar.py
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

Para comprobar una instancia recuperada de San Carlos ya reincorporada por el integrante 2, ejecutar `make integrante3-setup` e instalar nuevamente el ZIP: el empaquetado usa el puerto de `pg-recovery` (`SIGTEC_PORT_RECOVERY`, 55436) según `.distributed-state/routes.json`, y los estilos vuelven a distribuirse al reemplazo con una ranura nueva.

## Uso diario

Al iniciar sesión, sin configurar nada más, el complemento:

* carga las ocho capas en el grupo **SIG-TEC** y, al fondo, **OpenStreetMap** con su atribución visible;
* centra el mapa en los edificios del campus de la cuenta y muestra los nombres según la escala;
* activa el panel **Capas** de QGIS y abre el **panel SIG-TEC** a la derecha.

### Panel SIG-TEC

| Elemento | Función |
|---|---|
| Usuario, campus, conexión, mapa base | Sesión y estado de los nodos, comprobado cada 20 s sin bloquear QGIS |
| Indicador verde / ámbar | Campus que la cuenta puede editar; ámbar si el campus visible es solo de consulta |
| Selector de campus · **Centrar** | Solo mueven el mapa: no cambian la cuenta, el nodo ni los permisos |
| **Todos los campus** | Vista nacional con un rótulo por campus |
| Leyenda y capas | Simbología de las ocho capas; la casilla muestra u oculta cada una |
| **Actualizar capas** | Relee los datos sin tocar ediciones en curso |
| **Cerrar sesión** | Retira solo lo de SIG-TEC; pide confirmación si hay cambios sin guardar. Las credenciales guardadas se conservan |

El panel se abre o cierra en **Base de datos > SIG-TEC > Panel SIG-TEC**. Sin Internet el panel lo avisa y las
capas institucionales siguen funcionando. Si el proyecto no tiene capas propias se fija en EPSG:5367; si las
tiene, se respeta su sistema. El origen de los datos está en [DATOS_GEOGRAFICOS.md](DATOS_GEOGRAFICOS.md).

Las ocho capas son:

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

Cada capa usa `id` como clave, `geom` como geometría y EPSG:5367. Todas contienen información de los cinco campus. Un nuevo inicio de sesión elimina solo las capas administradas previamente por el complemento y el mapa base, y coloca los nuevos, por lo que nunca se duplican ni se borran capas ajenas del proyecto.

### Editar datos propios

1. Activar edición en una capa y crear un objeto dentro del campus.
2. Dejar `id` y `campus_id` vacíos: PostgreSQL los asigna.
3. Completar los atributos obligatorios y guardar.
4. Modificar el objeto y guardar; luego eliminarlo y guardar de nuevo.

Los disparadores `INSTEAD OF` del integrante 2 enrutan el cambio a la tabla original. Un objeto ajeno se puede consultar, pero su actualización o eliminación devuelve “No se permite editar un campus ajeno” y no altera PostgreSQL. Tampoco se permite cambiar `id` o `campus_id`.

## Estilos institucionales

La fuente versionada está en `qgis_plugin/sigtec/styles/`. `make integrante3-setup` inserta esos ocho QML como estilos por defecto en el central y activa la publicación lógica `sigtec_styles`. El complemento intenta primero el estilo distribuido de la base y usa el QML local solo si todavía no llegó la réplica.

Los QML se generan con `scripts/integrante3/generar_estilos.py` (reglas, escalas, etiquetas e iconos propios incrustados en base64, para que se vean igual en cualquier equipo). Para cambiar un estilo, editar ese archivo y repetir:

```bash
"$(scripts/qgis_python.sh)" scripts/integrante3/generar_estilos.py
make integrante3-setup
```

Después, abrir la misma capa con dos cuentas de campus y comprobar la misma simbología. `make integrante3-verify` exige exactamente ocho estilos predeterminados en cada nodo.

## Mensajes y solución de errores

| Mensaje | Causa y acción |
|---|---|
| No se pudo autenticar contra el nodo central | Usuario/clave incorrectos, central detenido o `config.json` equivocado. Revisar `docker compose ps` sin compartir secretos. |
| QGIS abre su propia ventana de credenciales | Clave incorrecta: el proveedor PostgreSQL de QGIS pide otra antes de avisar al complemento. Cancelarla y volver a iniciar sesión desde SIG-TEC. |
| La cuenta no tiene un campus activo asignado | Revisar `auth.usuario_campus` y ejecutar `make integrante3-setup`. |
| El nodo `<campus>` no está accesible | Iniciar ese contenedor, corregir host/puerto o terminar la reincorporación. No se agrega un conjunto parcial de capas. |
| La vista `qgis.v_*` no existe | Ejecutar `make replication-setup` y después `make integrante3-setup`. |
| Master password stored in the keychain is not valid | El llavero guarda una contraseña maestra distinta de la del almacén. Escribir la actual cuando QGIS la pida (QGIS actualiza el llavero). Tras cinco fallos QGIS se bloquea hasta reiniciarlo. Si no se conoce, ver «Contraseña maestra». |
| QGIS no pudo guardar las credenciales | Crear/desbloquear la contraseña maestra en **Preferencias > Opciones > Autenticación**. |
| No se permite editar un campus ajeno | Comportamiento esperado; cancelar la edición de ese objeto. |

### Contraseña maestra

Protege el almacén `qgis-auth.db` del perfil y no puede recuperarse si se pierde. Para establecer otra: cerrar QGIS,
respaldar `qgis-auth.db` y apartarlo (no borrarlo), y volver a abrir QGIS, que crea un almacén nuevo. Se pierden
solo las credenciales guardadas en QGIS; las de los campus se vuelven a escribir en SIG-TEC. PostgreSQL no cambia.

El llavero identifica la entrada por el nombre del perfil: abrir QGIS Desktop con otro `--profiles-path` y un perfil
llamado `default` **sobrescribe la contraseña del perfil real**. Para pruebas usar `--profile` con otro nombre.

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

Prueba del complemento con PyQGIS real (nodos activos y QGIS 3.44 LTR instalado):

```bash
make qgis-test
```

Instala el ZIP en un perfil temporal y comprueba, con las cinco cuentas, inicio de sesión, ocho capas, estilos, dibujo, etiquetas, panel, mapa base, navegación por los cinco campus, edición propia y rechazo de la ajena; además, clave incorrecta, nodo inaccesible, falta de Internet, cierre de sesión y ausencia de duplicados. Solo sustituye la ventana de inicio de sesión y los cuadros de mensaje. `QGIS_PYTHON` permite indicar otro intérprete.

La verificación de `make integrante3-verify` inicia sesión con las cinco cuentas, comprueba la asignación de campus, exige que una clave incorrecta sea rechazada, revisa las 40 exposiciones de vistas (8 × 5) y espera los ocho estilos en cada nodo. La indisponibilidad se demuestra de forma segura deteniendo un campus, intentando iniciar sesión y volviéndolo a iniciar:

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
