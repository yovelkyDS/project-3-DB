# Hallazgos de auditoría — SIG-TEC, Integrante 1

Fecha: 20 de noviembre de 2026, America/Costa_Rica. Diagnóstico sobre los archivos originales, sin aplicar correcciones. No se encontraron motivos para clasificar un hallazgo como CRÍTICO. Dos hallazgos ALTOS bloquean el cierre de la entrega; los demás tienen alternativas o afectan capacidades adicionales.

| ID | Severidad | Hallazgo | Bloquea entrega I1 |
|---|---|---|---|
| F-01 | ALTO | Los respaldos fallidos se registran como exitosos y devuelven código 0 | Sí |
| F-02 | ALTO | El modo de IDs explícitos carece de autorización y permite duplicados concurrentes entre capas | Sí |
| F-03 | MEDIO | La marca RECUPERADA falla y el orquestador PITR oculta el error | No, por sí solo |
| F-04 | MEDIO | El chequeo de puertos ignora los valores de `.env` | No; requiere exportar variables |
| F-05 | MEDIO | `APPLY=0` activa eliminación en el objetivo de retención | No; no usar esa variante |
| F-09 | MEDIO | Los manifiestos toman conteos del nodo vivo después de la copia | No; riesgo con actividad concurrente |
| F-06 | BAJO / MEJORA | TLS disponible, pero el servidor admite conexiones sin cifrar | No; endurecimiento opcional |
| F-07 | BAJO / MEJORA | El instalador PowerShell sin Bash no agrega variables nuevas | No; revisión estática, Windows sin verificar |
| F-08 | BAJO / MEJORA | La documentación identifica una imagen distinta de la efectivamente desplegada | No |

## F-01 — Falso éxito de respaldo

**Requisito:** estrategias de respaldo por nodo (profesor, p. 13); procedimiento reproducible de respaldo/restauración (distribución, p. 2); propagación de errores solicitada en esta auditoría.

**Ubicación:** `scripts/backup/logical_backup.sh:22–24,50–60`; `scripts/backup/physical_backup.sh:23–28,54–64`; contexto `scripts/lib/db.sh:7`.

**Evidencia ejecutada:** `raw/adversarial.json`, pruebas `logical_backup_wrong_password` y `physical_backup_wrong_password`. Se sustituyó exclusivamente en el contenedor efímero del laboratorio la contraseña de respaldo por un valor deliberadamente incorrecto, con salida en `/tmp/audit-negative-*`. Ambos comandos devolvieron **0**. El lógico imprimió `OK central: 0 bytes, 0 entradas TOC`; el físico imprimió `OK central: 0 MiB, inicio` pese a carecer de copia base y manifest. PostgreSQL rechazó la autenticación. No se escribió ningún respaldo fallido en los volúmenes originales.

**Explicación:** `backup_node` se invoca dentro de `if ! ( ... )`. En ese contexto Bash no aplica `errexit` a los comandos interiores como el autor espera. Las fallas de `pg_dump`, `pg_basebackup` y `pg_verifybackup` no interrumpen la función; el último `log` exitoso determina su resultado. Las ramas que deberían registrar ERROR no se alcanzan y se escribe OK en la bitácora.

**Riesgo:** aceptar archivos vacíos o copias inexistentes como respaldo vigente, y alimentar una demostración PITR con una copia inválida. Los respaldos válidos existentes sí fueron restaurados: el defecto afecta la confiabilidad del procedimiento ante fallas, no demuestra corrupción de esas copias.

**Corrección recomendada:** comprobar explícitamente el resultado de cada comando crítico, devolver fallo inmediatamente y escribir manifiesto/OK únicamente tras todas las validaciones. Usar directorios de trabajo que se publiquen como completos solo al terminar. Probar autenticación incorrecta, almacenamiento no escribible y rechazo de `pg_verifybackup`. No basta con añadir otro `set -e` dentro de la misma invocación condicional.

**Responsable:** Integrante 1. **Bloquea:** sí, por resultados falsos en una función central de recuperación.

## F-02 — IDs explícitos sin autorización y unicidad no atómica

**Requisito:** identificador global por objeto (profesor, p. 7); ID asignado por PostgreSQL, secuencia común y estabilidad (contrato, p. 6); protección frente a inserción manual solicitada por el usuario.

**Ubicación:** `sql/migrations/campus/0102_identificadores.sql:34–85`, especialmente 61 y 75–83. Las PK en `sql/schema/capas_locales.sql` solo garantizan unicidad dentro de cada tabla.

**Evidencia ejecutada:** `raw/adversarial.json`. En Cartago del laboratorio se creó `audit_editor`, sin superusuario, sin LOGIN y sin privilegios de secuencia; solo USAGE del esquema y SELECT/INSERT en dos capas. Bajo `SET ROLE audit_editor`, `has_sequence_privilege(...,'USAGE')` dio `false`, pero `SET LOCAL sigtec.permitir_id_explicito=on` permitió insertar `1000000042`. Después, dos sesiones insertaron **1000000043** en `puntos_interes` e `iluminacion`, respectivamente. Ambas confirmaron y una consulta posterior devolvió `1000000043 | 2`.

**Explicación:** una variable personalizada de sesión no acredita un privilegio de mantenimiento. La función SECURITY DEFINER confía solo en su valor. Además, los ocho `SELECT EXISTS` no serializan las inserciones concurrentes: una sesión no ve la fila no confirmada de la otra y cada PK acepta el ID en una tabla diferente.

**Límite de la demostración:** hoy no existen cuentas QGIS. Se modeló un escritor con permisos mínimos, no se afirma que una cuenta final actual sea explotable. El camino de inserción automática ordinario sí pasó las pruebas. Las futuras vistas podrían reducir el riesgo descartando IDs suministrados, pero eso no arregla la autorización de mantenimiento ni la unicidad global prometida por esta infraestructura.

**Riesgo:** reintroducir IDs arbitrarios ya emitidos y producir dos objetos con el mismo identificador global; trasladar esa ambigüedad al central y a las copias.

**Corrección recomendada:** restringir la operación de mantenimiento a una identidad/rol autorizado mediante un mecanismo que siga siendo seguro dentro de SECURITY DEFINER. Mantener una reserva global con restricción UNIQUE o serializar y volver a comprobar los IDs explícitos con una estrategia segura bajo la concurrencia soportada; una comprobación independiente por tabla no basta. Agregar migración nueva, no editar silenciosamente una ya aplicada. Repetir pruebas con rol de edición y dos sesiones.

**Responsable:** Integrante 1; coordinar el contrato de inserción con Integrante 2. **Bloquea:** sí, por una violación comprobada de integridad del identificador global. No exige reconstruir las bases existentes.

## F-03 — Error oculto en la marca de recuperación

**Requisito:** trazabilidad y confiabilidad de la demostración, no la existencia de una marca llamada RECUPERADA en el enunciado.

**Ubicación:** `scripts/recovery/pitr_steps.sh:94–98`; `scripts/recovery/pitr_demo.sh:22,42,108–112`; también la validación del original en 119–122 solo imprime resultados y no los convierte en aserciones.

**Evidencia ejecutada:** `raw/adversarial.json`, prueba `pitr_marker_command`: código **1**, `syntax error at or near ":"`, en `VALUES (:'run', ...)`. El PITR completo, sin embargo, devolvió 0 y declaró EXITOSA. `raw/pitr_direct.json` confirma que ambas instancias recuperadas contienen la marca A, pero ninguna RECUPERADA.

**Explicación:** las variables de psql usadas así en `-c` llegan al servidor sin interpolar. El pipeline de `t()` termina en `grep`, sin `pipefail`, por lo que una línea de error puede hacer que la función termine con éxito; en este paso además se descarta la salida. La verificación A/B independiente confirma que la recuperación de datos sí funcionó.

**Corrección:** usar stdin/archivo SQL para interpolar las variables; preservar el código del comando en los pipelines; convertir las comprobaciones del original y del orden temporal en aserciones. No declarar éxito si falla un paso requerido de la demostración.

**Responsable:** Integrante 1. **Bloquea:** no por sí solo, dado que el PITR fue confirmado directamente; debe corregirse para una demostración sin errores ocultos.

## F-04 — Configuración alternativa de puertos ignorada

**Requisito:** instalación y despliegue reproducibles del Integrante 1. Los números de puerto son acuerdos del equipo, no una imposición del profesor.

**Ubicación:** `scripts/setup.sh:71–76`; `scripts/check_prereqs.sh:116–131`, que usa `node_port` sin cargar `.env`.

**Evidencia:** la instalación aislada inicial terminó con código 1 (`raw/clean_setup.log`). Tras detener el laboratorio, con `.env` ya generado y puertos 56430–56436 libres, el chequeo volvió a buscar 55430–55436 y falló. Exportar los valores correctos produjo código 0 (`raw/configuration_probes.json`). La configuración original no fue cambiada.

**Riesgo:** otro integrante que siga la indicación de cambiar puertos en `.env` no supera el chequeo en una máquina con los puertos predeterminados ocupados.

**Corrección:** resolver la configuración efectiva antes del chequeo, incluyendo el primer arranque sin `.env`, y mostrar los puertos realmente inspeccionados. Documentar mientras tanto la exportación de variables.

**Responsable:** Integrante 1. **Bloquea:** no, existe una alternativa comprobada; la instalación con puertos libres predeterminados no fue refutada.

## F-05 — `APPLY=0` se interpreta como permiso de borrado

**Requisito:** seguridad operativa de la retención; herramienta adicional del equipo, no requisito académico explícito.

**Ubicación:** `Makefile:87–88`.

**Evidencia no destructiva:** `make -n wal-retention APPLY=0` produjo `scripts/backup/wal_retention.sh all --keep ${KEEP:-2} --apply` (`raw/configuration_probes.json`). No se ejecutó esa orden ni se eliminó ningún volumen o WAL.

**Explicación/riesgo:** `$(if $(APPLY),...)` evalúa cualquier texto no vacío como verdadero, incluido `0`; una automatización que use 0 para simulación ejecutaría el borrado real.

**Corrección:** aceptar exactamente `1` para aplicar y rechazar otros valores ambiguos; añadir una comprobación de expansión del comando. `make wal-retention` sin APPLY sí permaneció en simulación y funcionó.

**Responsable:** Integrante 1. **Bloquea:** no, no usar la variante defectuosa; corregir antes de automatizar retención.

## F-09 — Manifiesto ajeno al punto consistente de la copia

**Requisito:** verificación fiable del contenido respaldado, criterio de esta auditoría y del procedimiento de restauración de I1.

**Ubicación:** `scripts/backup/logical_backup.sh:22,30–33`; `scripts/backup/physical_backup.sh:23–27,34–36`; comparaciones en ambos scripts de restore.

**Evidencia estática:** después de terminar la copia y, en el caso físico, su verificación, se consulta otra vez el nodo vivo para obtener conteos y secuencia. No hay snapshot SQL compartido ni extracción de esos metadatos desde la copia recuperada. Una confirmación entre ambas operaciones queda en el manifiesto y puede no estar en el respaldo.

**Límite:** no se reprodujo deliberadamente una carrera durante el backup. Las copias concretas restauradas en esta auditoría sí coincidieron con sus manifiestos. El hallazgo no afirma que los archivos de backup sean inconsistentes: los mecanismos nativos mantienen su propia consistencia.

**Riesgo:** una copia sana puede declararse defectuosa al restaurarla por compararla con conteos posteriores; la secuencia requiere además considerar su comportamiento no transaccional y recuperación WAL.

**Corrección:** distinguir metadatos informativos del nodo vivo de aserciones sobre el backup. Para datos lógicos, coordinar un snapshot consistente cuando corresponda; para verificar una copia física, obtener las expectativas desde el punto recuperado o un procedimiento controlado. Probar el caso con escrituras concurrentes.

**Responsable:** Integrante 1. **Bloquea:** no en el escenario académico comprobado con conteos coincidentes; debe resolverse antes de usar esa comparación como garantía bajo carga.

## F-06 — Cifrado opcional en el servidor

**Requisito:** recomendación de ingeniería. El profesor no obliga TLS y no se clasifica como incumplimiento académico.

**Ubicación:** `docker/postgis/conf/pg_hba.conf:14–19`; `docker/postgis/conf/postgresql.conf:16–21`; afirmaciones generales en README sobre conexiones TLS.

**Evidencia:** `raw/adversarial.json`, `transport_without_tls`: `PGSSLMODE=disable` se conectó al central del laboratorio y `pg_stat_ssl.ssl` dio `false`. Las conexiones con `sslmode=require` y los verificadores SCRAM sí fueron confirmados en los seis originales.

**Riesgo:** al abrir puertos a otra máquina, el servidor no exige cifrado; SCRAM autentica, pero no cifra el resto de los datos.

**Corrección:** si el equipo decide exigir TLS, usar reglas `hostssl` y rechazar TCP sin TLS, incluyendo respaldo físico. En cualquier caso documentar “TLS disponible, usar sslmode=require”, distinguiéndolo de cifrado obligatorio.

**Responsable:** Integrante 1 con Integrantes 2/3 para los clientes. **Bloquea:** no; endurecimiento opcional.

## F-07 — Diferencia de actualización en PowerShell

**Requisito:** promesa del instalador equivalente; Windows no es una plataforma obligatoria del enunciado.

**Ubicación:** `scripts/setup.ps1:47–54,64–83`, frente a `scripts/setup.sh:51–65`.

**Evidencia estática:** PowerShell solo recorre variables que ya existen en `.env`. Si falta una clave agregada posteriormente a `.env.example`, no la incorpora ni genera su secreto. Bash sí agrega claves faltantes. Afecta el flujo sin Bash, por ejemplo al introducir la futura contraseña de replicación propuesta en `docs/INTEGRATION.md`, sección 2.5.

**Riesgo/corrección:** comportamiento de actualización distinto entre plataformas; sincronizar claves nuevas sin reemplazar valores existentes y verificar en Windows real. No se afirma haber ejecutado PowerShell.

**Responsable:** Integrante 1. **Bloquea:** no; portabilidad ejecutada en Windows sigue NO VERIFICADA.

## F-08 — Identidad de imagen documental obsoleta

**Requisito:** exactitud documental, no una versión de software incorrecta.

**Ubicación:** `docs/DEPENDENCIES.md:47`.

**Evidencia:** se declara `sha256:bfef9795…48ec8`; los seis contenedores originales usan `sha256:cc0beda012c0d724bfb69afb0734bc5ac872a5d38db73417305b49dca17402af`, registrado en `raw/*_container.json`. PostgreSQL y PostGIS sí coinciden con las versiones declaradas.

**Riesgo/corrección:** confusión al asociar evidencia con una construcción. Regenerar el inventario de versiones y asociar informes a hashes completos de imagen y fuentes. La carpeta actual no tiene `.git`; no se pudo establecer historial o commit, pero Git es recomendado, no obligatorio.

**Responsable:** Integrante 1. **Bloquea:** no.
