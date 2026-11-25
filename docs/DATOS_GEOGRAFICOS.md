# Datos geográficos: fuentes, licencia y alcance

## Fuente y licencia

* **OpenStreetMap**, extraído por la API 0.6 el 24 de noviembre de 2026. © colaboradores de
  OpenStreetMap, **ODbL 1.0** (<https://www.openstreetmap.org/copyright>). `data/osm/*.geojson` es
  una base derivada y se distribuye bajo la misma licencia. El mapa base usa las teselas de
  OpenStreetMap según su [política de uso](https://operations.osmfoundation.org/policies/tiles/).
* **TEC**: <https://www.tec.ac.cr/ubicaciones/centro-academico-alajuela> («Dentro de la Sede Central de
  la UTN en Villa Bonita de Alajuela»), usado solo para decidir qué recinto corresponde a Alajuela.

Cada objeto conserva su referencia (`way/…`), versión y fecha de OSM en el GeoJSON y, una vez
importado, en `ops.procedencia_objetos` de su campus.

| Campus | Límite en OSM | Observaciones |
|---|---|---|
| Cartago | way/40819609 | El mejor mapeado: 152 de 154 edificios con nombre |
| San José | way/199579277 | Polígono esquemático; se añaden por nombre las casas SJ-2, SJ-5, SJ-8 y SJ-9. Se excluye TEORética (ajena al TEC) |
| San Carlos | way/351554216 | 49 de 61 edificios no tienen nombre en OSM |
| Alajuela | way/316304753 (UTN) | El TEC funciona en la UTN. Solo «TEC Oficinas Administrativas CAA» (way/1483197688) es del TEC; lo demás lleva «UTN». Se excluye el nodo 14250954024, que contradice la página oficial |
| Limón | way/665308676 | Cinco edificios y un parqueo |

## Qué es real y qué es sintético

Objetos cargados (real = OSM; sint. = demostración):

| Capa | Cartago | San José | San Carlos | Alajuela | Limón |
|---|---|---|---|---|---|
| Edificios | 154 | 14 | 61 | 22 | 5 |
| Carreteras | 137 | 84 | 38 | 47 | 37 |
| Aceras | 263 | 7 ¹ | 160 | 10 | 1 ¹ |
| Parqueos | 11 | 21 ¹ | 22 | 2 | 1 |
| Zonas verdes | 13 | 27 ¹ | 7 | 8 | 3 ¹ |
| Puntos de interés | 49 | 21 ² | 20 | 8 | 5 ² |
| Iluminación | 250 sint. | 6 sint. | 131 sint. | 43 sint. | 10 sint. |
| Accesibilidad | 1 + 4 sint. | 4 sint. | 4 sint. | 4 sint. | 4 sint. |

¹ Objetos reales del **entorno** (hasta 250 m en San José y 200 m en Limón) porque el campus no
los tiene mapeados; en general no pertenecen al TEC. ² Los parqueos y parques del entorno lo dicen en su descripción.

* **Iluminación**: OSM no registra luminarias. Se colocan cada ~45 m sobre recorridos reales, con
  código `SINT-<campus>-L###`. Ni su posición ni su potencia o estado son reales.
* **Accesibilidad**: solo Cartago tiene un tramo etiquetado como accesible. Los demás son
  demostración; su descripción empieza por «DATO SINTÉTICO» y se dibujan en violeta discontinuo.
  **No certifican accesibilidad.**

Los nombres no se inventan: si OSM no lo informa se guarda «Edificio/Vía sin nombre en OSM» y el mapa
no lo rotula. Se corrigen solo erratas evidentes (lista `CORRECCIONES` del convertidor).

**Atributos supuestos.** El modelo exige datos que OSM no siempre trae. El valor supuesto se anota por
objeto en `ops.procedencia_objetos.supuestos`:

| Capa | Supuesto |
|---|---|
| edificios | `pisos` = 1 sin `building:levels`; `codigo` = `OSM-W<id>`; `area` calculada |
| carreteras | `superficie` = asfalto (lastre en `track`); `tipo` derivado de `highway` |
| aceras | `material` = otro, `ancho` = 1,5 m, `condicion` = regular |
| parqueos | `capacidad` ≈ área / 25 m² (3 motos, 1,5 bicicletas); `disponibilidad` = capacidad; `tipo` = general |
| zonas verdes | tipo de vegetación de parques y canchas sin más detalle |

```sql
-- En el nodo de cada campus
SELECT capa, fuente, count(*) FROM ops.procedencia_objetos GROUP BY 1, 2 ORDER BY 1, 2;
```

## Carga y reproducción

```bash
make datos-reales                                  # idempotente; respalda cada campus antes
python3 scripts/datos/preparar_osm.py --descargar  # regenera data/osm desde OSM
```

`make datos-reales` (incluido en `make install`) importa cada campus en una transacción: archiva los 41
objetos sintéticos en `ops.datos_retirados`, los retira y carga los reales sin enviar `id` (lo asigna
el disparador; los anteriores no se reutilizan). La replicación distribuye el resultado. Las tablas
`ops.*` no se replican. Una carga ya registrada como `datos_osm_v1` no se repite.

El juego sintético (`sql/seed/datos_sinteticos_v1.sql`) sigue siendo la base reproducible de las pruebas
aisladas y de CI.

## Limitaciones

* OSM es colaborativo: puede haber omisiones, posiciones aproximadas o cambios posteriores a la fecha indicada.
* Los nombres de escuelas y servicios son los de OSM; no se cotejaron uno a uno con el TEC.
* La paleta se inspira en los colores institucionales; no reproduce el manual de marca ni su logotipo.
