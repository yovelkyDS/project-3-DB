# Veredicto final

**NO APROBADO.** Existen dos defectos ALTOS comprobados que impiden declarar cerrada la entrega del Integrante 1: falsos éxitos de respaldo y protección insuficiente del identificador global.

| Pregunta | Respuesta |
|---|---|
| ¿Está terminada la responsabilidad del Integrante 1? | **No.** La implementación principal funciona, pero faltan corregir F-01 y F-02. |
| ¿Cumple los requisitos oficiales del profesor? | Arquitectura, PostGIS, capas y recuperación tienen evidencia positiva. La garantía de identificadores globales falla bajo una prueba admitida por la implementación. No se certifica el cumplimiento completo del proyecto ni se penalizan funciones de I2/I3. |
| ¿Es reproducible? | **Sí en macOS arm64, con observación:** se desplegaron seis nodos desde volúmenes nuevos, se compiló sin caché y se repitió el instalador sin cambiar datos/credenciales. Los puertos alternativos requieren exportar variables por F-04. Linux host y Windows no fueron probados. |
| ¿Respaldos y PITR funcionan? | **Sí en el camino exitoso:** seis restores lógicos y seis arranques físicos de originales; siete copias físicas verificadas; PITR A/B previo corroborado y uno nuevo aislado. **No son confiables ante fallas:** los scripts de backup devolvieron 0 y OK con autenticación inválida. El demo además oculta el error de su marca RECUPERADA. |
| ¿Está preparada para el Integrante 2? | Las bases existentes permiten empezar sin reconstrucción. Plantilla de 40 tablas compatible y publicación limitada comprobadas. La entrega definitiva queda bloqueada por F-01/F-02. Replicación completa y reincorporación son de I2 y no se certificaron. |
| ¿Hay defectos que impidan entregar? | **Sí:** F-01 y F-02. No se detectó corrupción en los datos originales; el duplicado se produjo solo en el laboratorio. |
| ¿Correcciones mínimas? | Comprobar y propagar cada fallo de respaldo; autorizar realmente el mantenimiento de IDs y garantizar unicidad bajo concurrencia mediante migración nueva. Reparar también la marca/pipelines PITR y documentar o corregir el chequeo de puertos antes de la demostración final. |

La suite ordinaria pasó **292/292**; las pruebas adversas revelaron los defectos que esa suite no cubre. En Cartago aislado, un rol sin privilegios de secuencia insertó un ID explícito y dos sesiones confirmaron el mismo **1000000043** en dos capas. No es una objeción de estilo ni una exigencia de producción adicional.

Se preservaron los 69 archivos originales inventariados y todos los datos geográficos de los cinco campus y `pg-recovery`, comprobados mediante hashes. No se aplicó ninguna corrección. El laboratorio quedó detenido y sus volúmenes se conservaron. Los nodos originales permanecen activos.

Detalle: [informe completo](AUDIT_REPORT.md), [hallazgos](FINDINGS.md), [pruebas](TEST_RESULTS.md), [preparación de integración](INTEGRATION_READINESS.md).
