# Preparación para el Integrante 2

**Diagnóstico de entrega: BLOQUEADA POR DEFECTOS TÉCNICOS (F-01 y F-02).**

**Capacidad de empezar a trabajar: sí, puede comenzar la replicación sobre las bases existentes sin reconstruirlas.** La estructura y la configuración habilitante son compatibles; el bloqueo es para declarar terminada y entregar como confiable la responsabilidad del Integrante 1. Las correcciones caben en scripts y una migración nueva.

## Lo que se verificó

| Interfaz | Resultado |
|---|---|
| Seis bases sigtec y PostGIS | Conexiones reales a seis servidores independientes; PostgreSQL 17.12/PostGIS 3.5.4 |
| Red y conexiones | DNS interno pg-central/pg-cartago/pg-san-jose/pg-san-carlos/pg-alajuela/pg-limon, puerto 5432; 55430–55435 desde el host, 127.0.0.1 |
| Originales | Ocho tablas por campus en su `local_<campus>`; PK bigint, campus_id smallint, tipos geométricos explícitos 5367 |
| Destinos centrales | Plantilla aplicada en central temporal: 40 tablas; firmas coincidentes con los cinco orígenes; sin secuencia ni triggers de asignación |
| Publicabilidad | CREATE PUBLICATION de las ocho tablas de San José funcionó en una transacción revertida del laboratorio |
| UPDATE/DELETE | Replica identity DEFAULT con PK id en las 40 tablas; no se requieren cambios de PK para comenzar |
| Configuración | wal_level logical; slots/senders 16/16; max_logical_replication_workers 8; max_worker_processes 16 |
| IDs automáticos | Fórmula y secuencia común verificadas; ID/campus inmutables por triggers en el camino ordinario |
| Permisos actuales | postgres para administración; sigtec_backup con REPLICATION y lectura; no existe aún rol específico de replicación ni cuentas QGIS |
| Estado del central original | Sin copias locales aplicadas todavía; es una plantilla que ejecutará I2, no una omisión de su implementación |

Evidencias: `raw/*_sql.json`, `raw/original_network_tls.log`, `raw/lab_full_tests.log`, `raw/integration_probe.log`, `raw/uncached_image_template_test.log`.

## Cambios que necesita I1 antes de cerrar la entrega

1. **F-01:** dar códigos no cero y registrar ERROR ante fallas de dump/basebackup/verificación; nunca publicar una copia incompleta como OK.
2. **F-02:** autorizar realmente el mantenimiento de IDs y proteger la unicidad entre capas frente a dos sesiones. Distribuirlo como una migración nueva que preserve las filas actuales.
3. Corregir la marca RECUPERADA y la propagación de fallos del demo PITR (F-03); es un arreglo pequeño y evita entregar una demostración con un paso silenciosamente fallido.
4. Incorporar a la guía la alternativa comprobada para puertos (F-04) hasta corregir su chequeo. Corregir la interpretación de APPLY (F-05) antes de automatizar retención.

Las bases originales tienen 207 IDs distintos y no requieren reparación de datos por esta auditoría. El duplicado de demostración está únicamente en el laboratorio detenido.

## Contrato de inserción y seguridad para I2

Los INSTEAD OF deben insertar sin `id` (o con NULL), comprobar el campus de sesión y devolver `RETURNING id`. No deben trasladar un ID arbitrario del formulario ni usar `sigtec.permitir_id_explicito` como autorización. Las cuentas finales carecerán de escritura directa en originales/copias según el contrato; actualmente todavía no existen.

Crear un rol específico de replicación con LOGIN/REPLICATION y el acceso SELECT/USAGE necesario, más las autorizaciones para crear la suscripción/publicación según la cuenta administrativa elegida. La regla HBA de conexión normal admite replicación lógica a una base concreta, con contraseña; la regla especial `replication` está reservada a sigtec_backup para el protocolo físico. Comprobar ambos permisos y transporte con ese rol cuando I2 lo cree. TLS fue probado con `sslmode=require`; el servidor actualmente también acepta `disable`.

Las tablas publicadas y sus destinos deben conservar el nombre calificado. La plantilla ya lo hace. Mantener DDL sincronizado: la replicación lógica no propaga cambios de esquema ni el estado de las secuencias. Esto lo documenta PostgreSQL en sus [restricciones de replicación lógica](https://www.postgresql.org/docs/17/logical-replication-restrictions.html).

No se ejecutó una suscripción con transferencia end-to-end ni se certifica la futura consolidación de nivel 2. Esos componentes son de I2. La compatibilidad de catálogos y la publicación limitada sí se ejecutaron.

## Recuperación y reincorporación

Las recomendaciones existentes de no publicar `ops`, reconciliar cambios posteriores y ajustar secuencias son pertinentes, pero no bastan para una reincorporación completa:

| Punto | Evaluación y acción necesaria |
|---|---|
| `ops` | Excluir de ambos niveles. node_info, migraciones y marcas son locales y colisionarían o perderían significado al distribuirse. |
| Slots | No asumir que un slot del publicador original se transportó al respaldo. Inventariar/recrear los slots necesarios y asociarlos al nuevo publicador; evitar dejar slots abandonados en el anterior. |
| Publicaciones | Forman parte del catálogo y pueden sobrevivir en la copia física si existían al tomarla. Inspeccionarlas; no ejecutar CREATE a ciegas. La indicación documental de “recrear publicación/ranura” requiere distinguir ambos objetos. |
| Suscripciones | Un respaldo físico copia catálogos que pueden contener suscripciones activas. La demo actual no tenía ninguna. Antes de arrancar una recuperación futura conectada a la misma red, aislar sus conexiones de salida y decidir cuáles deshabilitar/recrear. `--no-subscriptions` protege el restore lógico de prueba, no el arranque de una copia física. |
| Dos instancias del mismo campus | La original y la recuperada comparten identidad de campus y origen físico. No habilitar escritura/replicación simultánea de ambas; seleccionar el nodo autorizado y retirar la ruta anterior antes de volver a operar. |
| Filas posteriores al objetivo | Ajustar la secuencia no elimina B ni revierte las actualizaciones que ya llegaron al central. Comparar por id y contenido, decidir política de pérdida/reconciliación y verificar también eliminaciones. |
| Secuencia | La plantilla usa greatest y evita retroceder respecto al valor conocido. Tomar un máximo confiable de todas las ocho capas y de las copias pertinentes antes de abrir escrituras, incluyendo cualquier rango reservado que el diseño futuro requiera. La prueba no certifica una reconciliación final. |
| Segunda ruta | Recrear la salida campus→central no restablece por sí sola central→campus. Inventariar ambas rutas y su estado de sincronización; verificar INSERT/UPDATE/DELETE y filas por identificador en todos los destinos. |
| `copy_data` | Elegir estrategia según el estado de las tablas destino. Habilitar copia inicial sobre filas ya presentes puede causar conflictos; deshabilitarla sin reconciliar puede dejar pérdidas. |
| Retención | Mantener el basebackup y WAL de la ventana elegida hasta terminar las verificaciones. No aplicar retención basada en directorios de copias incompletas. |

Estos son riesgos concretos para la integración futura, no funcionalidades que se exigió implementar a I1 en esta auditoría. El nodo `pg-recovery` original permanece disponible para que I2 inspeccione el resultado real.

## Transacciones distribuidas

`max_prepared_transactions=0` en los seis nodos: PREPARE TRANSACTION no está habilitado actualmente. El escenario de transacción distribuida pertenece a I2 y el contrato presenta 2PC como una posibilidad, no una obligación ya fijada. Si el equipo elige 2PC, coordinar el parámetro, su presupuesto y el reinicio con I1, y crear el coordinador de decisiones correspondiente. No requiere reconstruir datos y no se usa como motivo de rechazo de esta entrega.

## Condición de aceptación posterior

Para liberar el cierre: repetir pruebas negativas de respaldo con salida no cero, rechazar IDs explícitos de un escritor ordinario y comprobar que dos sesiones no puedan confirmar un duplicado global. Después ejecutar el flujo ordinario de instalación/restauración/PITR sin errores ocultos. I2 puede avanzar con las estructuras actuales mientras se corrigen esos puntos, manteniendo deshabilitado el acceso de edición final que podría activar F-02.
