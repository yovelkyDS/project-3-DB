# Auditoría técnica final — SIG-TEC, Integrante 1

**Veredicto: NO APROBADO.**

Fecha: 20 de noviembre de 2026. Host: macOS arm64; zona America/Costa_Rica. Alcance: arquitectura, PostGIS, identificadores, datos, despliegue, respaldos, WAL, PITR e interfaces del Integrante 1. No se aplicaron correcciones.

## Resumen ejecutivo

La infraestructura principal existe y funciona. Se comprobaron seis clústeres PostgreSQL independientes, PostGIS en sigtec, 40 tablas originales con geometría correcta, restauraciones lógicas y físicas de los seis nodos y recuperación PITR con A conservado/B excluido. La instalación aislada y su segunda ejecución conservaron datos y credenciales; también se recompiló PostGIS sin caché de construcción.

Sin embargo, dos defectos ALTOS impiden declarar terminada la responsabilidad de I1:

1. Los scripts de respaldo devuelven **0** y registran **OK** aunque la autenticación falle y no exista una copia utilizable.
2. El modo de mantenimiento de IDs puede activarlo un escritor sin permiso sobre la secuencia. Dos sesiones confirmaron el mismo **1000000043** en capas distintas en el laboratorio.

La suite ordinaria pasó **292/292** antes de las pruebas adversas. Ese resultado es real, pero no cubre los dos defectos anteriores. No se encontraron duplicados ni alteraciones en las bases originales: todas las escrituras de prueba se hicieron en recursos separados.

El Integrante 2 **puede comenzar sin reconstruir las bases**: hay PK compatibles, nombres calificados coherentes, parámetros lógicos habilitados y una plantilla central validada de 40 tablas. La entrega definitiva queda pendiente de corregir la fiabilidad de respaldo y la integridad de IDs. No se exige a I1 implementar la replicación ni las vistas de los demás integrantes.

## Fuentes, precedencia y alcance académico

1. [Enunciado oficial](</Users/allanaron06122005gmail.com/Downloads/Tercer Proyecto Bases II.pdf>): p. 3 arquitectura; p. 7 capas/SRID/ID global/campus; p. 9 estrategia distribuida; p. 13 respaldo y recuperación; p. 15 evaluación.
2. [Distribución y contrato](</Users/allanaron06122005gmail.com/Downloads/BDII_project3_distribution.pdf>): pp. 1–2 tareas y aceptación de I1; pp. 3–6 contrato propuesto.
3. Archivos y configuración efectivos de esta carpeta; definiciones SQL y estado de contenedores consultados directamente.
4. Informes previos de `evidence/`, tratados como hipótesis y corroborados cuando se indica.
5. Documentación primaria de PostgreSQL para aclaraciones puntuales.

Los dos PDF se extrajeron completos a `reference/`; se renderizaron páginas relevantes y se revisaron visualmente las tablas de capas, respaldo, responsabilidades e IDs. Los documentos son fuentes de requisitos, no autorización para ampliar esta auditoría a implementar el sistema completo. La solicitud pegada del usuario determina la misión, las restricciones y los entregables.

| Clase | Ejemplos | Tratamiento |
|---|---|---|
| Obligación del profesor | Cinco campus + central, PostGIS, ocho capas y geometrías, referencia espacial definida, ID global/campus, pg_dump, pg_basebackup, WAL, PITR y restauración de un nodo | Se evalúan dentro del alcance asignado a I1. |
| Responsabilidad de I1 | Instalación de seis nodos, modelo común, datos de prueba, respaldo/restauración, demostración aislada, diagrama, diccionario y guías | Se contrasta código, estado y reproducibilidad. |
| Acuerdo propuesto del equipo | PostgreSQL 17.12/PostGIS 3.5.4, sigtec, puertos 55430–55435, esquemas local_*, EPSG:5367 y fórmula campus×10⁹+secuencia | Se verifica compatibilidad contractual; no se atribuyen estos valores exactos al profesor. |
| Ingeniería adicional | TLS obligatorio, pinning de todos los paquetes Debian, respaldos fuera de máquina, programación automática y retención avanzada | No se convierten en requisitos académicos. Solo se señalan riesgos concretos. |
| Trabajo de I2/I3 | Replicación final, global, qgis, INSTEAD OF, transacción distribuida, auth, cuentas QGIS, PyQGIS y estilos | Fuera de esta implementación; se revisan interfaces y riesgos. |

El enunciado tiene dos fechas de entrega distintas: noviembre en portada y junio en administración. La documentación ya lo reconoce. No se resolvió esa contradicción ni se usó para juzgar la implementación.

## Metodología y preservación

Se leyeron las fuentes, se inventariaron archivos, se inspeccionaron scripts antes de ejecutarlos y luego se separaron las pruebas:

- **Originales:** consultas SQL de solo lectura, inspección filtrada de Docker, logs y montaje de backups/WAL en solo lectura para copiarlos a un contenedor efímero sin red.
- **Laboratorio:** copia de fuentes bajo `audit/lab/`, proyecto `sigtec_audit_20261120`, red propia, puertos **56430–56436**, etiqueta `sigtec-audit/postgis:17.12-3.5.4`, volúmenes nuevos y siete secretos nuevos. No se copió `.env` original. Las únicas adaptaciones de la plantilla fueron identidad del proyecto, imagen y puertos; SQL/scripts/Dockerfile se conservaron.
- **Pruebas adversas:** roles, IDs explícitos, concurrencia, contraseñas incorrectas y falla SIGKILL solo dentro de ese proyecto temporal.

No se ejecutó limpieza destructiva, no se eliminó ningún volumen y no se cambió una contraseña original. La parada final afectó únicamente a los siete contenedores del laboratorio. Se conservaron sus volúmenes para revisión. Los seis nodos originales y la recuperación previa siguen healthy.

`raw/final_integrity.json` confirma **69 archivos originales sin cambios**, mismos hashes de todas las filas geográficas en los cinco campus y recuperación, y ausencia de valores secretos originales en los otros archivos escaneados. Esto verifica preservación de esas filas y archivos; no pretende congelar contadores operativos o WAL que PostgreSQL genera normalmente.

## Estado del entorno y arquitectura

| Nodo | Puerto publicado | Campus/esquema | Objetos actuales | Observación |
|---|---|---|---:|---|
| pg-central | 127.0.0.1:55430 | Sin campus propio | Sin capas originales | ops y PostGIS; plantillas para copias aún no aplicadas por I2 |
| pg-cartago | 127.0.0.1:55431 | 1 / local_cartago | 41 | Datos de semilla |
| pg-san-jose | 127.0.0.1:55432 | 2 / local_san_jose | 41 | Datos de semilla |
| pg-san-carlos | 127.0.0.1:55433 | 3 / local_san_carlos | 43 | 41 de semilla + A y B de demo anterior |
| pg-alajuela | 127.0.0.1:55434 | 4 / local_alajuela | 41 | Datos de semilla |
| pg-limon | 127.0.0.1:55435 | 5 / local_limon | 41 | Datos de semilla |
| pg-recovery | 127.0.0.1:55436 | Recuperación de San Carlos | 42 | A conservado, B excluido; timeline 2 |

Las seis instancias originales tienen **system_identifier distintos**, data mounts distintos y archivos WAL archivados distintos en `sigtec_net`. La recuperada conserva el system_identifier de San Carlos, como corresponde a una copia física del clúster, y usa datos/archivo propios. No se cuenta como séptimo origen independiente.

Versiones reales: PostgreSQL **17.12**, PostGIS **3.5.4**, GEOS **3.15.0**, PROJ **9.9.0**; Docker cliente/servidor **29.2.1**, Compose **5.0.2**. La imagen original en ejecución es `sha256:cc0beda012c0d724bfb69afb0734bc5ac872a5d38db73417305b49dca17402af`.

Los healthchecks usan pg_isready. Se comprobaron además base, extensión, esquemas, catálogos y conexiones reales: healthy por sí solo no acredita ese modelo. Los volúmenes WAL separados son de **archivado**; el WAL activo pg_wal permanece en PGDATA. Todo sigue en una misma máquina Docker: no se probó tolerancia a perder ese host completo ni se exige una distribución física en varias máquinas que el enunciado no impone expresamente.

## Modelo geográfico e identificadores

Se verificaron Polygon para edificios/parqueos/zonas_verdes; LineString para carreteras/aceras/accesibilidad; Point para puntos_interes/iluminacion. Todas las capas originales tienen geom NOT NULL, typmod 5367, restricciones de validez/no vacío, PK id bigint, campus_id smallint y GiST. Las columnas específicas del enunciado están presentes; la disponibilidad de parqueos se interpreta como cantidad entre 0 y capacidad, una decisión documentada del equipo.

Hay una secuencia local por campus compartida por ocho triggers de asignación, otros ocho de inmutabilidad y límites 1–999999999 sin ciclo. Las inserciones automáticas, rechazo de modificación de id/campus, dominios, geometría incorrecta y SRID distinto se probaron en el laboratorio. Las definiciones actuales y ACL originales están guardadas en `raw/original_function_definitions.json`.

Los **207 IDs actuales originales son distintos**, con fórmula y campus correctos. La afirmación previa de 205 describe la semilla inicial; 207 incluye la demo PITR y no es un incumplimiento. La garantía futura es insuficiente por F-02: el camino explícito está abierto mediante una variable de sesión y la consulta de existencia no es atómica entre tablas. PostgreSQL acepta variables personalizadas de dos componentes; su valor no representa una autorización de usuario, según la [documentación de opciones personalizadas](https://www.postgresql.org/docs/17/runtime-config-custom.html).

Las geometrías están dentro del rango de Costa Rica y alrededor de las referencias declaradas, a escala de campus; las extensiones transformadas se conservaron por capa. San Carlos usa el ejemplo del contrato. La ubicación aproximada de San José es coherente con Barrio Amón, descrito en la [página institucional del TEC](https://www.tec.ac.cr/campus-tecnologico-local-san-jose). No se hizo un levantamiento catastral ni se certifica que cada objeto sintético represente un edificio real o esté dentro de un lindero oficial; eso no fue requerido.

## Instalación, dependencias y reproducibilidad

Se inspeccionaron Makefile, Compose, instaladores, initdb, migraciones, semilla, utilidades y referencias locales. No se identificaron componentes locales referenciados imprescindibles que falten, rutas absolutas del desarrollador utilizadas como dependencia o archivos temporales externos necesarios. La raíz actual carece de `.git`; el historial y la versión previamente publicada no son verificables. No se convierte esa ausencia en incumplimiento: el profesor recomienda control de versiones.

La imagen parte de un digest de PostgreSQL y compila un tarball PostGIS comprobado con SHA-256. Se hizo una instalación con seis PGDATA nuevos y después una **construcción --no-cache**, seguida de otro setup completo y de la validación de plantilla usando esa imagen. No se borró la imagen base del daemon: se acredita reconstrucción de capas y descargas de dependencias, no un Docker host totalmente virgen sin imágenes de ningún tipo.

La segunda ejecución conservó todas las filas y el archivo de credenciales. Se generaron siete secretos de 32 caracteres alfanuméricos, diferentes entre sí y con `.env` en modo 600. Las migraciones y semilla están registradas y no se reaplicaron/duplicaron. PostgreSQL se ejecuta dentro de Linux, pero el host probado fue macOS; eso no equivale a haber probado el instalador sobre Linux host.

La limitación real de instalación es F-04: el chequeo previo no lee la configuración de puertos. Exportarla permitió el despliegue. Linux host y Windows siguen **NO VERIFICADOS**; se detectó una diferencia estática del flujo PowerShell sin Bash (F-07). Las dependencias Debian/GEOS/PROJ no están fijadas a versiones exactas, limitación ya documentada: el resultado es funcionalmente reproducible hoy, no una construcción bit a bit garantizada en el futuro.

## Respaldos, WAL y restauración

Se copiaron los respaldos originales a almacenamiento efímero con todos los orígenes en `:ro`. Sin acceso de red, se ejecutó de nuevo pg_verifybackup sobre **siete directorios**: uno por nodo, más una segunda copia de San Carlos. Todos pasaron. Después se restauró el dump más reciente de cada uno de los seis nodos y se arrancó el último respaldo físico de cada nodo con recovery_target immediate. PostGIS, identidad, conteos y validación espacial coincidieron; los restores lógicos también comprobaron secuencias y triggers.

Esto distingue tres resultados: archivo legible, copia física verificada y copia restaurada/arrancada. Aquí hay evidencia independiente de los tres; no se aceptó pg_verifybackup como sustituto de un arranque. También se generaron y restauraron nuevas copias de los seis nodos del laboratorio.

El archivado está activo y los seis nodos reportaban **failed_count=0** al inspeccionarlos. El PITR consumió WAL real del archivo correspondiente. La política manual conserva los N físicos más recientes y WAL desde el más antiguo retenido; la simulación funcionó en los seis nodos del laboratorio. No hay programación automática de copias o purga, ni retención automática del histórico lógico. Si no se opera la política, backups y archivos pueden crecer sin cota. Es un límite operativo documentable, no una obligación de cron impuesta por el profesor.

**F-01 impide aprobar el procedimiento ante errores:** la prueba con contraseña incorrecta obtuvo código 0 y OK sin respaldo válido. **F-05** hace peligroso usar APPLY=0. Ninguno refuta las restauraciones exitosas realmente ejecutadas, pero ambos deben distinguirse de la confiabilidad global de la automatización.

**F-09 (revisión estática):** los manifiestos recogen conteos/secuencia mediante consultas posteriores a la copia, no desde un snapshot compartido con pg_dump/pg_basebackup. Por inspección, una escritura concurrente podría hacer que el manifiesto no describa exactamente el punto copiado. Las pruebas aquí verifican copias concretas cuyos conteos coincidieron; no se certifica esa comparación como prueba universal bajo carga concurrente. Es un riesgo adicional para I1 al ampliar la automatización.

## PITR: evaluación crítica

Se corroboró la corrida anterior **20261120T172854Z** con el log del contenedor real y consultas SQL sobre original/recuperada. En UTC: commit A **17:28:57.799862** < objetivo **17:29:00.365787** < commit B **17:29:02.879970**. PostgreSQL registró recuperación temporal, reproducción de WAL, detención antes de un commit posterior al objetivo, promoción y timeline **2**. La recuperada tiene A previo, no B; el original tiene A modificado y B.

Se repitió independientemente en `sigtec_audit_20261120`, corrida **20261120T202335Z**. En UTC: A **20:23:39.092490** < objetivo **20:23:41.550941** < B **20:23:43.971695**. El origen temporal se sometió a SIGKILL y se reinició; la recuperación usó sus propios volúmenes, respaldo y WAL. A conservó la descripción anterior, B quedó fuera y timeline cambió 1→2. La recuperación original no se reinició ni reemplazó.

La recuperación de datos es **funcional**. El paso de registrar RECUPERADA falla con sintaxis psql y el pipeline lo oculta (F-03); no es correcto afirmar que todo el script está libre de fallos. La [documentación de psql -c](https://www.postgresql.org/docs/17/app-psql.html) explica que su cadena SQL se envía al servidor; debe usarse un archivo/stdin para las interpolaciones previstas en ese paso.

No se ejecutó la prueba temporal A/B en cada uno de los otros nodos. Se verificaron sus backups/restores y el código común; el demo automatizado exige campus. La recuperación completa a un instante en cada origen, con replicación activa, sigue sin certificar.

## Seguridad y operación

Se confirmaron puertos localhost, verificadores SCRAM, cuenta de respaldo sin superusuario/creación de roles/bases, revocaciones de esquemas y secuencias a PUBLIC y search_path fijo en la función SECURITY DEFINER. No se encontró el valor de un secreto original en los otros archivos escaneados. `.gitignore` excluye `.env`, pero, al no existir historial Git aquí, no se prueba que nunca haya sido publicado en otro lugar.

TLS funciona con certificado autofirmado; el servidor no lo exige (F-06). Las cuentas finales y los permisos de edición pertenecen a I2/I3 y todavía no existen. El superusuario común a los seis nodos es la cuenta administrativa de desarrollo; no se le exige autenticación institucional a I1. La vulnerabilidad de IDs se relaciona con una función de su modelo y sí debe corregirse antes de confiar en esa interfaz.

Los backups y WAL están en volúmenes de la misma máquina y contienen datos sensibles; la guía da una exportación externa, pero esta auditoría no probó desastre total del host ni almacenamiento remoto. El entrypoint usa root para preparar propietarios/certificados y delega al proceso PostgreSQL; no se exige eliminar esos preparativos de inicialización. Los scripts destructivos existen separados con confirmación; no fueron ejecutados.

## Preparación para integración y revisión documental

La comparación de firmas dio cinco esquemas × ocho tablas compatibles. Una publicación de ocho tablas funcionó en el laboratorio y fue revertida; no se implementó replicación completa. El central original está preparado mediante plantilla, no con sus destinos ya aplicados. La ausencia de publicaciones, suscripciones, auth, global, qgis y PyQGIS es coherente con el reparto de tareas.

No publicar ops es correcto. Ajustar la secuencia y recrear conexiones tras PITR es necesario según la estrategia, pero no resuelve por sí solo las filas que ya llegaron al central ni la ruta de retorno. La copia física futura también puede contener suscripciones activas: aislar conexiones antes de arrancarla, elegir un único origen de escritura, reconciliar ambas rutas y verificar filas. Las publicaciones pueden estar en el catálogo restaurado; no deben recrearse a ciegas. Véase [diagnóstico de integración](INTEGRATION_READINESS.md).

`max_prepared_transactions=0`: si I2 elige 2PC tendrá que coordinar su habilitación y un coordinador. No se clasifica como incumplimiento de I1 porque el contrato propone 2PC condicionalmente y el alcance del profesor no fija ese mecanismo específico.

README, arquitectura, diccionario, guías de instalación/backup/integración y guion de demo cubren los componentes principales. Las discrepancias concretas son F-03/F-04 y la imagen obsoleta F-08; la portabilidad ya se declara no ejecutada. El guion de I1 estima 6–8 minutos, mientras el profesor limita el video integral a 10 minutos: I3 deberá editar el conjunto; no se auditó ni se generó el video final.

## Matriz de cumplimiento

| Requisito | Obligatorio u opcional | Evidencia | Estado | Observaciones |
|---|---|---|---|---|
| Cinco nodos operativos + central | Profesor; I1 | Inspect, seis system_identifier y conexiones | APROBADO | Instancias independientes en una máquina. |
| sigtec/PostGIS en seis nodos | Profesor + nombre/versión del equipo | version/postgis_full_version reales | APROBADO | 17.12 / 3.5.4. |
| Ocho capas × cinco campus, atributos y geometrías | Profesor; I1 | Catálogos, SQL y 40 validaciones de capa | APROBADO | 40 tablas originales. |
| Referencia espacial definida y transformación | Profesor; 5367 es decisión de equipo | Typmod, ST_SRID y seed ST_Transform | APROBADO | No se exige un SRID exacto distinto. |
| Datos geográficos de prueba | Distribución I1 | Semilla 205; actual 207; extensiones | APROBADO CON OBSERVACIONES | Sintéticos, proximidad aproximada; no levantamiento real. |
| IDs automáticos, fórmula y secuencia compartida | Profesor ID global; fórmula contractual | Suite y catálogos | APROBADO CON OBSERVACIONES | Camino ordinario correcto; véase garantía completa abajo. |
| Unicidad/protección de ID ante inserción manual | Profesor ID global + contrato | Dos sesiones confirmaron mismo ID en dos capas | NO APROBADO | F-02. |
| Inmutabilidad id/campus y restricciones de nodo | Contrato, apoya pertenencia oficial | Suite SQL y triggers reales | APROBADO | Bajo operaciones ordinarias, no contra el superusuario que cambie DDL. |
| Generación pg_dump por nodo | Profesor; I1 | Nuevas copias de laboratorio | APROBADO CON OBSERVACIONES | Camino exitoso; F-01 ante fallas. |
| Restauración lógica por nodo | Distribución I1 | Seis originales + seis laboratorio | APROBADO | No se restauró sobre datos originales. |
| pg_basebackup por nodo | Profesor; I1 | Siete originales verificados y seis nuevos | APROBADO CON OBSERVACIONES | F-01 afecta reporte de errores. |
| Arranque desde copias físicas | Profesor recuperación; I1 | Seis originales + seis laboratorio | APROBADO | Distinto de solo verificar manifest. |
| Archivado WAL | Profesor; I1 | pg_stat_archiver y reproducción PITR | APROBADO | Archivo separado; mismo host. |
| PITR temporal de un nodo y falla simulada | Profesor y distribución I1 | Corrida previa corroborada + corrida nueva A/B | APROBADO CON OBSERVACIONES | Datos correctos; F-03 en marca final. |
| PITR A/B individual de cada otro nodo | Procedimiento por nodo, extensión de cobertura | Código común; sin repetición temporal en todos | NO VERIFICADO | No confundir con sus restores físicos immediate. |
| Automatización robusta de fallos de respaldo | Distribución I1 + criterio de auditoría | Contraseña inválida → OK/código 0 | NO APROBADO | F-01. |
| Instalación desde volúmenes nuevos | Distribución I1 | Setup aislado, imagen propia y --no-cache | APROBADO CON OBSERVACIONES | F-04 exige exportar puertos alternativos. |
| Idempotencia y persistencia | Criterio de auditoría de I1 | --full y segundo setup con hashes | APROBADO | Filas/credenciales conservadas. |
| Windows y Linux host | Plataformas previstas, no requisito oficial específico | Inspección; sin host de esas plataformas | NO VERIFICADO | Linux de contenedores no equivale a host Linux; F-07. |
| Preparación de replicación | Interfaz I1→I2 | Parámetros, plantilla y publicación revertida | APROBADO CON OBSERVACIONES | Inicio sin reconstruir viable; cierre sujeto F-01/F-02. |
| Guías, topología, diccionario e interfaces | Distribución I1; documentación oficial | docs y referencias revisadas | APROBADO CON OBSERVACIONES | Imagen obsoleta y comandos afectados por hallazgos. |
| Política de retención y simulación | Herramienta extra del equipo | Simulación y make -n | APROBADO CON OBSERVACIONES | Simulación funciona; F-05; borrado real no ejecutado. |
| TLS/SCRAM | Decisión de ingeniería | TLS real/SCRAM booleano; sslmode=disable aceptado | APROBADO CON OBSERVACIONES | TLS disponible, no obligatorio; F-06 opcional. |
| Replicación final, vistas, INSTEAD OF y transacción distribuida | Profesor, responsabilidad I2 | No implementados en este alcance | FUERA DE ALCANCE | No se usa su ausencia para rechazar I1. |
| Auth, cuentas, PyQGIS y estilos | Profesor/distribución I3 | No implementados en este alcance | FUERA DE ALCANCE | Variables de contraseña generadas solamente. |
| Reincorporación completa tras PITR | Distribución I2, coordinación I1/I3 | Solo recuperación independiente | FUERA DE ALCANCE | Riesgos y pasos pendientes documentados. |
| Video y demostración integral | Profesor; ensamblaje I3 | Guion I1, sin video final | FUERA DE ALCANCE | No se certifica entrega académica integral. |

## Hallazgos, correcciones mínimas y conclusión

Registro completo en [FINDINGS.md](FINDINGS.md): **2 ALTOS, 4 MEDIOS y 3 BAJOS/MEJORA**. No se inventó un hallazgo crítico por la ausencia de funciones ajenas al alcance.

Correcciones bloqueantes: **F-01**, comprobar resultados de backup/verificación y rechazar copias incompletas; **F-02**, autorizar mantenimiento y asegurar unicidad concurrente. Deben acompañarse de pruebas negativas que fallen antes del arreglo y pasen después. Aplicar como nuevas migraciones cuando corresponda, conservando las bases.

Antes de la demostración final conviene resolver también el error concreto de RECUPERADA y la pérdida de códigos del pipeline, el chequeo de puertos y la interpretación de APPLY. Las otras observaciones no impiden por sí solas trabajar con la infraestructura.

**I1 no debe dar su implementación por terminada todavía.** Hay evidencia sólida de arquitectura, modelo y recuperación funcional; el rechazo responde a fallas reproducidas de confiabilidad e integridad, no a falta de replicación, QGIS o características de producción. Tras corregir y revalidar los dos bloqueos, no se observó una necesidad de reemplazar la arquitectura ni reconstruir sus datos.

Entregables complementarios: [pruebas y comandos](TEST_RESULTS.md), [integración](INTEGRATION_READINESS.md), [veredicto breve](FINAL_VERDICT.md). Evidencia original preservada en `evidence/`; evidencia nueva en `audit/raw/` y `audit/lab/evidence/`.
