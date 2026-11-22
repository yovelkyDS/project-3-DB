# Hallazgos — segunda auditoría independiente

**Un bloqueo ALTO: RA-01, continuación de F-02 en el nodo recuperado anterior a 0103.** Los defectos F-01/F-02 de los campus migrados están reparados. No se identificaron hallazgos CRÍTICOS.

| Hallazgo | Severidad | Estado | Bloquea cierre I1 |
|---|---|---|---|
| F-01 falso éxito de respaldo | ALTO original | CERRADO en pruebas ejecutadas | No |
| F-02 IDs explícitos/concurrencia | ALTO original | CERRADO en cinco campus activos; persiste en recuperación antigua | Sí, mediante RA-01 |
| **RA-01 recuperación antigua vulnerable y migración con falso éxito** | **ALTO** | **ABIERTO, REPRODUCIDO** | **Sí** |
| F-03 marca RECUPERADA/pipeline | MEDIO original | Corregido, componentes ejecutados | No |
| F-04 puertos de .env | MEDIO original | Corregido en escenario ejecutado | No |
| F-05 APPLY=0 | MEDIO original | Corregido, simulación ejecutada | No |
| F-06 TLS opcional | BAJO / mejora | ABIERTO, reproducido | No |
| F-07 PowerShell sin claves nuevas | BAJO / portabilidad | ABIERTO, estático | No |
| F-08 identidad de imagen | BAJO / reproducibilidad | Documento actualizado; cambio efectivo corroborado | No |
| F-09 manifiesto fuera del snapshot | MEDIO | ABIERTO, ahora reproducido | No, en alcance académico de aceptación anterior |

## RA-01 — El nodo recuperado que se conserva para I2 sigue expuesto a F-02

**Requisito:** I1 entrega una recuperación aislada utilizable por I2; la remediación requiere protección global de IDs y una vía segura para respaldos anteriores a 0103. No se exige a I1 implementar la reincorporación distribuida.

**Ubicaciones:** `scripts/db/migrate.sh:64`; `scripts/lib/nodes.sh:90–101` y `node_valid`; `remediation/INTEGRATION_IMPACT.md:37–39`; `remediation/GLOBAL_ID_FIX.md:115`; dependencia nueva del registro en `sql/templates/ajustar_secuencia_tras_recuperacion.sql:22`.

**Evidencia directa:**

1. Consultas de solo lectura muestran `sigtec-pg-recovery-1` con 0101/0102, sin 0103 ni `ops.identificadores_globales`; los cinco campus activos sí están migrados.
2. En el laboratorio, tanto `scripts/db/migrate.sh recovery` como **`make migrate NODE=recovery`** imprimieron `nodo inválido: recovery` y devolvieron **0**. `make migrate` sin NODE usa all y solo recorre los seis activos. No es una ruta de actualización del recuperado.
3. Se tomó un dump del recuperado original y se restauró íntegramente en un clúster efímero sin red. Un editor NOLOGIN, sin USAGE de secuencia y con SELECT/INSERT solo en dos capas, activó el GUC. Dos conexiones confirmaron **3000000083** en `puntos_interes` e `iluminacion`: `FIRST_RC=0 SECOND_RC=0 CONFIRMED_ROWS=2`.

Fuentes: `raw/inventory_before.json`, `raw/legacy_recovery_reproduction.json`, `raw/make_migrate_recovery.log`. El original no recibió esas filas. La reproducción ocurrió exclusivamente en su copia efímera.

**Causa:** la actualización no separa identidad lógica del campus y destino físico de conexión. El catálogo rechaza recovery y el error de expansión se pierde en una sustitución de comando usada como lista de `for`. La guía remite a un comando que no actualiza esa instancia. El ajuste de secuencia exige una tabla que allí no existe.

**Impacto:** las pruebas verdes del estado nuevo no protegen una recuperación de respaldo antiguo. Seguir la instrucción puede anunciar éxito y entregar a I2 un origen de escritura que aún admite el defecto ALTO original. La posibilidad de integrar las copias y vistas no cambia esta falta de garantía del modelo de I1.

**Corrección indispensable:** proporcionar y validar una ruta dirigida explícitamente al recuperado, con identidad obtenida/validada del campus restaurado; aplicar y registrar 0103 sin borrar datos, comprobar registro/triggers/secuencia y propagar errores de destino/migración. Documentar el comando correcto y probar desde un respaldo pre-0103 los rechazos de editor y la carrera autorizada. Como alternativa de entrega, identificar una recuperación nueva ya conforme y conservar la antigua como histórica, junto con el procedimiento seguro para futuras restauraciones antiguas. No basta con apuntar `NODE=san_carlos` al entorno actual: eso selecciona el campus activo y puede actualizar el destino equivocado.

**Responsable:** I1. No requiere replicación, QGIS, auth ni correcciones de I2/I3.

## F-09 — Metadatos posteriores provocan un falso rechazo de recuperación

**Severidad: MEDIO.** Antes solo estático; ahora reproducido con planificación controlada. Se envolvió temporalmente `pg_dump` desde `/tmp/PATH` para abrir una pausa después de terminar el dump y antes de obtener metadatos. Otra conexión confirmó una fila durante esa ventana. No se modificó el binario ni el script del proyecto.

El respaldo se publicó válido. `pg_restore` terminó sin errores; validación espacial, 24 triggers y registro fueron correctos. El restore-test devolvió **1** por `puntos_interes=99` esperado frente a `98` restaurado y secuencia `249` frente a `248`. Evidencia: `raw/residual_independent.json`.

**Corrección necesaria:** obtener las expectativas del mismo snapshot/punto recuperado o declarar los metadatos vivos estrictamente informativos y retirar su igualdad como condición de integridad. Tratar específicamente la secuencia, cuyo estado no equivale a un snapshot transaccional ordinario. Agregar una regresión con una escritura en esta ventana para lógico y físico. No se demostró una copia corrupta ni pérdida de datos por el mecanismo de respaldo. Se conserva la clasificación no bloqueante del primer informe; antes de usar este verificador como aceptación bajo carga sí debe resolverse.

## F-06 — TLS disponible, no exigido

**Severidad: BAJO / mejora; no bloquea.** La conexión real TCP con `sslmode=disable` funcionó y `pg_stat_ssl.ssl` fue false. HBA usa host y no impone hostssl. La guía debería decir TLS disponible y clientes con `sslmode=require`. Si se exige cifrado al abrir la infraestructura a otras máquinas, exigir hostssl/rechazo de tráfico sin TLS y probar clientes y backup físico. No se impone aquí como requisito académico nuevo.

## F-07 — Actualización desigual de `.env` en PowerShell

**Severidad: BAJO / portabilidad; no bloquea.** En la rama sin Bash, `setup.ps1` recorre solo el `.env` existente y sustituye marcadores; no incorpora claves nuevas de `.env.example`. El Bash sí lo hace. Corrección: fusionar claves ausentes sin reemplazar valores existentes y probar en Windows. Windows/PowerShell no se ejecutó en esta auditoría; este hallazgo no se presenta como reproducción dinámica.

## F-08 y límites de cobertura

El documento ya reconoce las dos imágenes. Se corroboró el cambio de etiqueta y se restauraron copias originales con la imagen actual. Conviene preservar un artefacto identificable de la construcción aceptada y el inventario de paquetes, y mantener etiqueta distinta para laboratorios. La misma etiqueta y versión no garantizan los mismos bytes después de reconstruir. No bloquea: se probó compatibilidad de datos.

Las 733 aserciones son legítimas, pero no detectaron RA-01 ni F-09. Añadir la transición de recuperación antigua y los códigos de destino inválido es parte de la aceptación de RA-01. Mejorar la comparación de idempotencia y el control de errores de su `&&`, y hacer explícita la comprobación de secuencia en el restore físico, son mejoras de cobertura; no se convierten en otros bloqueos.
