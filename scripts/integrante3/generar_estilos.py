"""Genera los ocho QML institucionales con PyQGIS. Ejecutar con el Python de QGIS 3.44:

  "$(scripts/qgis_python.sh)" scripts/integrante3/generar_estilos.py

Los QML quedan en qgis_plugin/sigtec/styles/; make integrante3-setup los publica en layer_styles.
Los iconos son dibujos propios incrustados en base64: no dependen de archivos del equipo.
"""
import base64
import os
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from qgis.PyQt.QtCore import QPointF, Qt  # noqa: E402
from qgis.PyQt.QtGui import QColor, QFont  # noqa: E402
from qgis.core import (  # noqa: E402
    Qgis, QgsApplication, QgsCentroidFillSymbolLayer, QgsFillSymbol,
    QgsLineSymbol, QgsMapLayer, QgsMapUnitScale, QgsMarkerLineSymbolLayer, QgsMarkerSymbol,
    QgsPalLayerSettings, QgsProperty, QgsRuleBasedLabeling, QgsRuleBasedRenderer, QgsSimpleFillSymbolLayer,
    QgsSimpleLineSymbolLayer, QgsSimpleMarkerSymbolLayer, QgsSvgMarkerSymbolLayer,
    QgsTextBufferSettings, QgsTextFormat, QgsUnitTypes, QgsVectorLayer,
)

OUT = Path(__file__).resolve().parents[2] / "qgis_plugin" / "sigtec" / "styles"
# Paleta inspirada en los azules y el rojo institucionales; no pretende ser el manual de marca.
AZUL, AZUL_MEDIO, AZUL_CLARO, ROJO = "#003B73", "#2E6DA8", "#B9D3EA", "#C8102E"
SIN_NOMBRE = "\"nombre\" NOT LIKE '%sin nombre en OSM%'"
METROS = QgsUnitTypes.RenderMetersInMapUnits
MM = QgsUnitTypes.RenderMillimeters

ICONOS = {  # dibujos propios de 24 x 24, en blanco
    "cajero": '<rect x="4" y="7" width="16" height="10" rx="1.5" fill="none" stroke="#fff" stroke-width="2"/><circle cx="12" cy="12" r="2.4" fill="#fff"/>',
    "laboratorio": '<path d="M10 4v6L5.5 18.5h13L14 10V4M8.5 4h7" fill="none" stroke="#fff" stroke-width="2" stroke-linejoin="round"/><path d="M8.6 14.5h6.8l1.4 3H7.2z" fill="#fff"/>',
    "soda": '<path d="M7 4v6a2 2 0 0 0 4 0V4M9 4v16" fill="none" stroke="#fff" stroke-width="1.8"/><path d="M16 4c-2 1-2.5 5-1.5 8H16v8" fill="none" stroke="#fff" stroke-width="1.8"/>',
    "biblioteca": '<path d="M12 7C10 5.500 7 5.200 4 5.800V18c3-.6 6-.3 8 1.200 2-1.500 5-1.800 8-1.200V5.800C17 5.200 14 5.500 12 7zM12 7v12" fill="none" stroke="#fff" stroke-width="1.8" stroke-linejoin="round"/>',
    "auditorio": '<path d="M9 4h6v7a3 3 0 0 1-6 0z" fill="#fff"/><path d="M6 11a6 6 0 0 0 12 0M12 17v3M9 20h6" fill="none" stroke="#fff" stroke-width="1.8"/>',
    "oficina": '<rect x="4" y="8" width="16" height="11" rx="1.500" fill="none" stroke="#fff" stroke-width="2"/><path d="M9 8V5h6v3M4 13h16" fill="none" stroke="#fff" stroke-width="2"/>',
    "parada_bus": '<rect x="6" y="4" width="12" height="13" rx="2" fill="#fff"/><rect x="8" y="6.500" width="8" height="4.500" fill="#1B5E8C"/><circle cx="9" cy="19" r="1.800" fill="#fff"/><circle cx="15" cy="19" r="1.800" fill="#fff"/>',
    "servicio_medico": '<path d="M10 5h4v5h5v4h-5v5h-4v-5H5v-4h5z" fill="#fff"/>',
    "parqueo": '<path d="M9 20V5h4.500a4.200 4.200 0 0 1 0 8.400H9" fill="none" stroke="#fff" stroke-width="3"/>',
    "otro": '<path d="M12 4l2.400 5 5.600.7-4.100 3.800 1.100 5.500-5-2.800-5 2.800 1.100-5.500L4 9.700 9.600 9z" fill="#fff"/>',
}


def icono(nombre):
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">{ICONOS[nombre]}</svg>'
    return "base64:" + base64.b64encode(svg.encode()).decode()


def ancho(minimo, maximo):
    scale = QgsMapUnitScale()
    scale.minSizeMMEnabled = scale.maxSizeMMEnabled = True
    scale.minSizeMM, scale.maxSizeMM = minimo, maximo
    return scale


def linea(color, width, unit=MM, scale=None, style=Qt.SolidLine, dash=None, alpha=255, cap=Qt.RoundCap):
    tone = QColor(color)
    tone.setAlpha(alpha)
    layer = QgsSimpleLineSymbolLayer(tone, width, style)
    layer.setWidthUnit(unit)
    if scale:
        layer.setWidthMapUnitScale(scale)
    if dash:
        layer.setUseCustomDashPattern(True)
        layer.setCustomDashVector(dash)
    layer.setPenCapStyle(Qt.FlatCap if dash else cap)
    layer.setPenJoinStyle(Qt.RoundJoin)
    return layer


def area(color, alpha, borde, grosor, style=Qt.SolidLine):
    tone = QColor(color)
    tone.setAlpha(alpha)
    return QgsSimpleFillSymbolLayer(tone, Qt.SolidPattern, QColor(borde), style, grosor, Qt.RoundJoin)


def simbolo(clase, *layers):
    symbol = clase()
    for layer in layers:
        symbol.appendSymbolLayer(layer)
    symbol.deleteSymbolLayer(0)
    return symbol


def reglas(items):
    """items: (etiqueta, filtro, símbolo, escala mínima 1:n o 0)"""
    root = QgsRuleBasedRenderer.Rule(None)
    for label, filtro, symbol, escala in items:
        rule = QgsRuleBasedRenderer.Rule(symbol, 0, escala, filtro or "", label)
        root.appendChild(rule)
    return QgsRuleBasedRenderer(root)


def texto(size, color, bold=False, italic=False, halo=0.9):
    fmt = QgsTextFormat()
    font = QFont("Arial")
    font.setBold(bold)
    font.setItalic(italic)
    fmt.setFont(font)
    fmt.setSize(size)
    fmt.setSizeUnit(QgsUnitTypes.RenderPoints)
    fmt.setColor(QColor(color))
    buf = QgsTextBufferSettings()
    buf.setEnabled(True)
    buf.setSize(halo)
    buf.setColor(QColor(255, 255, 255, 235))
    fmt.setBuffer(buf)
    return fmt


def etiqueta(fmt, escala, prioridad, placement, campo="nombre", envolver=0, **extra):
    s = QgsPalLayerSettings()
    s.fieldName = campo
    s.isExpression = campo != "nombre"
    s.setFormat(fmt)
    s.scaleVisibility = True
    s.minimumScale, s.maximumScale = escala, 1
    s.priority = prioridad
    s.placement = placement
    s.autoWrapLength = envolver
    for key, value in extra.items():
        setattr(s, key, value)
    return s


def etiquetado(items):
    root = QgsRuleBasedLabeling.Rule(None)
    for nombre, filtro, settings in items:
        rule = QgsRuleBasedLabeling.Rule(settings)
        rule.setDescription(nombre)
        rule.setFilterExpression(filtro)
        root.appendChild(rule)
    return QgsRuleBasedLabeling(root)


def guardar(capa, tipo, campos, renderer, labeling=None, alias=None, tip="", escala=0):
    layer = QgsVectorLayer(f"{tipo}?crs=EPSG:5367&" + "&".join(f"field={c}" for c in campos), capa, "memory")
    layer.setRenderer(renderer)
    if labeling:
        layer.setLabeling(labeling)
        layer.setLabelsEnabled(True)
    if escala:
        layer.setScaleBasedVisibility(True)
        layer.setMinimumScale(escala)
        layer.setMaximumScale(0)
    layer.setMapTipTemplate(tip)
    for campo, texto_alias in (alias or {}).items():
        layer.setFieldAlias(layer.fields().indexOf(campo), texto_alias)
    style = QgsMapLayer
    categorias = style.Symbology | style.Labeling | style.MapTips | style.Rendering
    message, ok = layer.saveNamedStyle(str(OUT / f"{capa}.qml"), categorias)
    if not ok:
        raise RuntimeError(message)
    # Sin espacios finales ni diferencias de fin de línea en el repositorio.
    path = OUT / f"{capa}.qml"
    path.write_text("\n".join(l.rstrip() for l in path.read_text("utf-8").splitlines()) + "\n", "utf-8")
    print("OK", capa)


def edificios():
    def edificio(relleno, alpha, borde, grosor):
        sombra = area("#1b2733", 70, "#1b2733", 0, Qt.NoPen)
        sombra.setOffset(QPointF(0.35, 0.35))
        return simbolo(QgsFillSymbol, sombra, area(relleno, alpha, borde, grosor))
    ajeno = "\"nombre\" LIKE '%UTN%'"
    renderer = reglas([
        ("Edificio institucional", f"{SIN_NOMBRE} AND NOT ({ajeno})", edificio(AZUL_CLARO, 235, AZUL, 0.45), 0),
        ("Edificio de la UTN (sede anfitriona)", ajeno, edificio("#E4DCCB", 230, "#8A7A5C", 0.35), 0),
        ("Edificio sin nombre registrado", f"NOT ({SIN_NOMBRE})", edificio("#DDE3EA", 225, "#7F8FA0", 0.3), 0),
    ])
    poly = Qgis.LabelPlacement.OverPoint
    clave = ("regexp_match(lower(\"nombre\"), '(biblioteca|auditorio|rector|administra|gimnasio|comedor|ctec|lcc|"
             "computaci|centro de las artes|casa |aulas|docencia|tec oficinas)') > 0")
    comun = dict(centroidInside=True, centroidWhole=True)
    labeling = etiquetado([
        ("Edificios principales", f"{SIN_NOMBRE} AND ({clave} OR \"area\" > 1500)",
         etiqueta(texto(8, AZUL, bold=True), 9000, 8, poly, envolver=20, **comun)),
        ("Demás edificios", f"{SIN_NOMBRE} AND NOT ({clave} OR \"area\" > 1500)",
         etiqueta(texto(7.5, "#23466B"), 2200, 5, poly, envolver=20, **comun)),
    ])
    # El icono del servicio va en el centro del edificio: el nombre se baja para no taparlo.
    for rule in labeling.rootRule().children():
        s = rule.settings()
        s.dataDefinedProperties().setProperty(QgsPalLayerSettings.Property.OffsetXY, QgsProperty.fromExpression(
            "if(regexp_match(lower(\"nombre\"), '(biblioteca|soda|comedor|restaurante|^laboratorio|auditorio|cajero|cl[ií]nica)') > 0, '0,5', '0,0')"))
        rule.setSettings(QgsPalLayerSettings(s))
    guardar("edificios", "Polygon", ["id:integer", "campus_id:integer", "nombre:string", "codigo:string", "area:double", "pisos:integer"],
            renderer, labeling, tip='<b>[% "nombre" %]</b><br>Código: [% "codigo" %]<br>Área: [% round("area") %] m²')


def carreteras():
    def via(casing, fill, w_in, mins, maxs):
        return simbolo(QgsLineSymbol,
                       linea(casing, w_in + 1.2, METROS, ancho(mins + 0.35, maxs + 0.6)),
                       linea(fill, w_in, METROS, ancho(mins, maxs)))
    items = [
        ("Vía principal", "\"tipo\" = 'principal'", via("#B4762A", "#FFD27A", 9, 0.9, 4.5), 0),
        ("Vía secundaria", "\"tipo\" = 'secundaria'", via("#A08F5A", "#FFF0B8", 7.5, 0.7, 3.8), 0),
        ("Calle interna", "\"tipo\" = 'interna'", via("#7D8791", "#FFFFFF", 6.5, 0.6, 3.4), 40000),
        ("Vía de servicio", "\"tipo\" = 'servicio'", via("#98A1AA", "#F7F7F5", 4.5, 0.4, 2.6), 20000),
        ("Acceso a parqueo", "\"tipo\" = 'acceso'", simbolo(
            QgsLineSymbol, linea("#A9B1B9", 4.2, METROS, ancho(0.5, 2.4)), linea("#ECEEF0", 3.2, METROS, ancho(0.3, 1.9))), 12000),
        ("Superficie de lastre o tierra", "\"superficie\" IN ('lastre','tierra')", simbolo(
            QgsLineSymbol, linea("#A67C45", 0.5, dash=[2.4, 1.6])), 12000),
    ]
    renderer = reglas(items)
    for rule in renderer.rootRule().children():   # bordes abajo, relleno arriba: cruces limpios
        for i in range(rule.symbol().symbolLayerCount()):
            rule.symbol().symbolLayer(i).setRenderingPass(i)
    renderer.setUsingSymbolLevels(True)
    labeling = etiquetado([("Nombre de vía", SIN_NOMBRE, etiqueta(
        texto(7, "#4A4030", italic=True), 6000, 4, Qgis.LabelPlacement.Curved))])
    for rule in labeling.rootRule().children():
        s = rule.settings()
        line = s.lineSettings()
        line.setMergeLines(True)
        line.setPlacementFlags(Qgis.LabelLinePlacementFlag.OnLine)
        s.setLineSettings(line)
        s.repeatDistance = 120
        rule.setSettings(s)
    guardar("carreteras", "LineString", ["id:integer", "campus_id:integer", "nombre:string", "tipo:string", "superficie:string"],
            renderer, labeling, tip='<b>[% "nombre" %]</b><br>[% "tipo" %] · [% "superficie" %]')


def aceras():
    renderer = reglas([
        ("Acera o sendero peatonal", "\"material\" <> 'lastre'", simbolo(
            QgsLineSymbol, linea("#FFFFFF", 2.4, METROS, ancho(0.55, 1.6), alpha=210),
            linea("#B5654A", 1.3, METROS, ancho(0.28, 0.8), dash=[2.2, 1.1])), 0),
        ("Sendero de lastre", "\"material\" = 'lastre'", simbolo(
            QgsLineSymbol, linea("#FFFFFF", 2.2, METROS, ancho(0.5, 1.4), alpha=190),
            linea("#8C6A3F", 1.1, METROS, ancho(0.25, 0.7), dash=[1, 1.3])), 0),
    ])
    guardar("aceras", "LineString", ["id:integer", "campus_id:integer", "material:string", "ancho:double", "condicion:string"],
            renderer, tip='Acera · [% "material" %]<br>Ancho: [% "ancho" %] m · condición [% "condicion" %]', escala=15000)


def parqueos():
    placa = simbolo(QgsMarkerSymbol,
                    QgsSimpleMarkerSymbolLayer(Qgis.MarkerShape.Square, 4, 0, Qgis.ScaleMethod.ScaleArea, QColor(AZUL_MEDIO), QColor("#FFFFFF")),
                    svg("parqueo", 3.2))
    centro = QgsCentroidFillSymbolLayer()
    centro.setSubSymbol(placa)
    centro.setPointOnSurface(True)
    base = lambda: area("#C9D2DE", 190, AZUL_MEDIO, 0.35, Qt.DashLine)  # noqa: E731
    guardar("parqueos", "Polygon", ["id:integer", "campus_id:integer", "capacidad:integer", "tipo:string", "disponibilidad:integer"],
            reglas([
                ("Parqueo", "", simbolo(QgsFillSymbol, base()), 0),
                ("Símbolo de parqueo", "", simbolo(QgsFillSymbol, centro), 6000),
            ]), tip='Parqueo [% "tipo" %]<br>Capacidad registrada o estimada por área: [% "capacidad" %]')


def zonas_verdes():
    tipos = [("Bosque", "bosque", "#4E8F57", "#3B7346"), ("Árboles", "arboles", "#68A566", "#4C8550"),
             ("Arbustos", "arbustos", "#8DB86C", "#6C9550"), ("Jardín", "jardin", "#A9D18E", "#7FAE63"),
             ("Césped o campo deportivo", "cesped", "#C4E3A6", "#93BD74"), ("Área verde mixta", "mixta", "#B5D6A0", "#86AE70")]
    guardar("zonas_verdes", "Polygon", ["id:integer", "campus_id:integer", "area:double", "tipo_vegetacion:string"],
            reglas([(n, f"\"tipo_vegetacion\" = '{t}'", simbolo(QgsFillSymbol, area(c, 120, b, 0.25)), 0) for n, t, c, b in tipos]),
            tip='Zona verde · [% "tipo_vegetacion" %]<br>[% round("area") %] m²')


def svg(nombre, size):
    layer = QgsSvgMarkerSymbolLayer(icono(nombre))
    layer.setSize(size)
    return layer


def punto(nombre, color, size=5.2, forma=Qgis.MarkerShape.Circle):
    disco = QgsSimpleMarkerSymbolLayer(forma, size, 0, Qgis.ScaleMethod.ScaleArea, QColor(color), QColor("#FFFFFF"))
    disco.setStrokeWidth(0.4)
    return simbolo(QgsMarkerSymbol, disco, svg(nombre, size * 0.68))


def puntos_interes():
    parqueo = "lower(\"nombre\") LIKE '%parqueo%'"
    tipos = [("Biblioteca", "biblioteca", AZUL), ("Laboratorio", "laboratorio", "#6A3D9A"), ("Auditorio", "auditorio", "#8E2A5B"),
             ("Soda o comedor", "soda", "#D9660B"), ("Servicio médico", "servicio_medico", ROJO), ("Cajero automático", "cajero", "#1E7B4F"),
             ("Parada de autobús", "parada_bus", "#1B5E8C"), ("Oficina o escuela", "oficina", "#54606C")]
    escalas = {"oficina": 5000, "cajero": 8000}
    items = [(n, f"\"tipo\" = '{t}'", punto(t, c), escalas.get(t, 12000)) for n, t, c in tipos]
    items += [("Parqueo con nombre", f"\"tipo\" = 'otro' AND {parqueo}", punto("parqueo", AZUL_MEDIO, 4.4, Qgis.MarkerShape.Square), 5000),
              ("Otro punto de interés", f"\"tipo\" = 'otro' AND NOT ({parqueo})", punto("otro", "#7A8792", 4.4), 8000)]
    # Las posiciones alrededor del punto evitan tapar el icono; el nombre del edificio homónimo
    # ya se rotula en su capa, por eso aquí no se repite.
    unico = "coalesce(\"descripcion\",'') NOT LIKE 'Ubicado en el edificio%'"
    place = Qgis.LabelPlacement.OrderedPositionsAroundPoint
    comun = dict(dist=2.6, envolver=20)
    labeling = etiquetado([
        ("Servicios", f"{unico} AND \"tipo\" IN ('biblioteca','soda','auditorio','servicio_medico','laboratorio')",
         etiqueta(texto(7.5, "#3A2A1A", bold=True), 4000, 7, place, **comun)),
        ("Transporte y cajeros", f"{unico} AND \"tipo\" IN ('parada_bus','cajero')",
         etiqueta(texto(7, "#1B4F72"), 2500, 4, place, **comun)),
        ("Parqueos", f"{unico} AND {parqueo}", etiqueta(texto(7, AZUL_MEDIO), 3000, 3, place, **comun)),
        ("Otros", f"{unico} AND \"tipo\" IN ('otro','oficina') AND NOT ({parqueo})",
         etiqueta(texto(7, "#40474E"), 2500, 3, place, **comun)),
    ])
    guardar("puntos_interes", "Point", ["id:integer", "campus_id:integer", "nombre:string", "tipo:string", "descripcion:string"],
            reglas(items), labeling, tip='<b>[% "nombre" %]</b><br>[% "descripcion" %]')


def iluminacion():
    def lampara(color, borde, alpha=255, style=Qt.SolidLine):
        halo = QgsSimpleMarkerSymbolLayer(Qgis.MarkerShape.Circle, 3.4, 0, Qgis.ScaleMethod.ScaleArea, QColor(255, 214, 90, 70), QColor(0, 0, 0, 0))
        tone = QColor(color)
        tone.setAlpha(alpha)
        foco = QgsSimpleMarkerSymbolLayer(Qgis.MarkerShape.Circle, 1.5, 0, Qgis.ScaleMethod.ScaleArea, tone, QColor(borde))
        foco.setStrokeWidth(0.25)
        foco.setStrokeStyle(style)
        return simbolo(QgsMarkerSymbol, halo, foco)
    sint = "\"codigo\" LIKE 'SINT-%'"
    guardar("iluminacion", "Point", ["id:integer", "campus_id:integer", "codigo:string", "potencia:integer", "estado:string"],
            reglas([
                ("Luminaria funcional", f"NOT ({sint}) AND \"estado\" = 'funcional'", lampara("#F5B800", "#7A5B00"), 0),
                ("Luminaria con incidencia", f"NOT ({sint}) AND \"estado\" <> 'funcional'", lampara(ROJO, "#6B0818"), 0),
                ("Luminaria sintética (demostración)", sint, lampara("#FFFFFF", "#B88A00", 230), 0),
            ]), tip='Luminaria [% "codigo" %]<br>[% "potencia" %] W · [% "estado" %]', escala=3000)


def accesibilidad():
    sint = "coalesce(\"descripcion\",'') LIKE '%SINTÉTICO%'"
    def ruta(color, dash=None):
        marca = QgsMarkerLineSymbolLayer(True, 9)
        marca.setSubSymbol(simbolo(QgsMarkerSymbol, QgsSimpleMarkerSymbolLayer(
            Qgis.MarkerShape.Circle, 1.7, 0, Qgis.ScaleMethod.ScaleArea, QColor("#FFFFFF"), QColor(color))))
        return simbolo(QgsLineSymbol, linea("#FFFFFF", 1.7), linea(color, 1.0, dash=dash), marca)
    guardar("accesibilidad", "LineString", ["id:integer", "campus_id:integer", "tipo:string", "condicion:string", "descripcion:string"],
            reglas([
                ("Ruta o paso accesible", f"NOT ({sint})", ruta("#0072CE"), 0),
                ("Accesibilidad sintética (demostración)", sint, ruta("#7E57C2", [2, 1.4]), 0),
            ]), tip='Accesibilidad · [% "tipo" %]<br>[% "descripcion" %]', escala=12000)


def main():
    app = QgsApplication([], False)
    app.initQgis()
    for build in (edificios, carreteras, aceras, parqueos, zonas_verdes, puntos_interes, iluminacion, accesibilidad):
        build()
    app.exitQgis()


if __name__ == "__main__":
    main()
