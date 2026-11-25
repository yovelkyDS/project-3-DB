"""Panel lateral SIG-TEC. Solo interfaz: las acciones se comunican por señales al complemento."""
from qgis.PyQt.QtCore import QEvent, QObject, QPointF, QRectF, QSize, Qt, pyqtSignal
from qgis.PyQt.QtGui import QColor, QFont, QPen
from qgis.PyQt.QtWidgets import (
    QComboBox, QFrame, QGridLayout, QHBoxLayout, QLabel, QPushButton, QScrollArea, QSizePolicy, QTreeWidget,
    QTreeWidgetItem, QVBoxLayout, QWidget,
)
from qgis.core import QgsCoordinateTransform, QgsProject, QgsSymbolLayerUtils
from qgis.gui import QgsDockWidget, QgsMapCanvasItem

from .core import CAMPUS_NAMES, NODE_CODES

STATES = {"ok": ("#1E7B4F", "●"), "parcial": ("#C77700", "●"), "error": ("#C8102E", "●"), "espera": ("#7A8792", "○")}
STYLE = """
#sigtecHeader { background: #003B73; border-radius: 4px; }
#sigtecHeader QLabel { color: white; }
#sigtecTitle { font-size: 17px; font-weight: bold; }
#sigtecEdit { border-radius: 4px; padding: 6px; }
QComboBox, QComboBox QAbstractItemView { color: palette(window-text); }
"""


class SigTecPanel(QgsDockWidget):
    login_requested = pyqtSignal()
    logout_requested = pyqtSignal()
    campus_selected = pyqtSignal(str)
    center_requested = pyqtSignal()
    all_requested = pyqtSignal()
    refresh_requested = pyqtSignal()
    layer_toggled = pyqtSignal(str, bool)

    def __init__(self, parent=None):
        super().__init__("SIG-TEC", parent)
        self.setObjectName("SigTecPanel")
        body = QWidget()
        body.setStyleSheet(STYLE)
        layout = QVBoxLayout(body)
        layout.setContentsMargins(8, 8, 8, 8)

        header = QFrame()
        header.setObjectName("sigtecHeader")
        head = QVBoxLayout(header)
        title = QLabel("SIG-TEC")
        title.setObjectName("sigtecTitle")
        subtitle = QLabel("Sistema de Información Geográfica distribuido de los campus del TEC")
        subtitle.setWordWrap(True)
        head.addWidget(title)
        head.addWidget(subtitle)
        layout.addWidget(header)

        grid = QGridLayout()
        grid.setColumnStretch(1, 1)
        self.user, self.campus = QLabel("—"), QLabel("—")
        self.status, self.basemap = QLabel(), QLabel()
        for row, (text, widget) in enumerate([("Usuario:", self.user), ("Campus:", self.campus),
                                              ("Conexión:", self.status), ("Mapa base:", self.basemap)]):
            label = QLabel(text)
            label.setStyleSheet("font-weight: bold;")
            widget.setWordWrap(True)
            grid.addWidget(label, row, 0, Qt.AlignTop)
            grid.addWidget(widget, row, 1)
        layout.addLayout(grid)

        self.edit = QLabel()
        self.edit.setObjectName("sigtecEdit")
        self.edit.setWordWrap(True)
        layout.addWidget(self.edit)

        layout.addWidget(self._section("Navegar entre campus"))
        self.selector = QComboBox()
        for code in NODE_CODES:
            self.selector.addItem(CAMPUS_NAMES[code], code)
        self.selector.setToolTip("Solo mueve el mapa. No cambia el campus que la cuenta puede editar.")
        self.selector.activated.connect(lambda _i: self.campus_selected.emit(self.selector.currentData()))
        layout.addWidget(self.selector)
        row = QHBoxLayout()
        self.center = self._button("Centrar", "Volver a encuadrar el campus seleccionado", self.center_requested)
        self.all = self._button("Todos los campus", "Ver los cinco campus en el mapa", self.all_requested)
        row.addWidget(self.center)
        row.addWidget(self.all)
        layout.addLayout(row)

        layout.addWidget(self._section("Leyenda y capas"))
        self.legend = QTreeWidget()
        self.legend.setHeaderHidden(True)
        self.legend.setIconSize(QSize(20, 16))
        self.legend.setMinimumHeight(190)
        self.legend.setToolTip("Marque o desmarque una capa para mostrarla u ocultarla.")
        self.legend.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.legend.itemChanged.connect(self._toggled)
        layout.addWidget(self.legend, 1)
        note = QLabel('Geografía: © <a href="https://www.openstreetmap.org/copyright">colaboradores de '
                      'OpenStreetMap</a> (ODbL). Lo marcado como «sintético» es demostración.')
        note.setWordWrap(True)
        note.setOpenExternalLinks(True)
        note.setStyleSheet("font-size: 10px;")
        layout.addWidget(note)

        row = QHBoxLayout()
        self.refresh = self._button("Actualizar capas", "Volver a leer los datos del nodo del campus", self.refresh_requested)
        self.session = QPushButton()
        self.session.clicked.connect(self._session_clicked)
        row.addWidget(self.refresh)
        row.addWidget(self.session)
        scroll = QScrollArea()   # en pantallas bajas se desplaza en lugar de recortar textos
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.NoFrame)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        scroll.setWidget(body)
        container = QWidget()    # los botones de sesión quedan siempre a la vista
        outer = QVBoxLayout(container)
        outer.setContentsMargins(0, 0, 0, 0)
        row.setContentsMargins(8, 0, 8, 8)
        outer.addWidget(scroll, 1)
        outer.addLayout(row)
        self.setWidget(container)
        self.setMinimumWidth(310)
        self.active = False
        self.clear()

    @staticmethod
    def _section(text):
        label = QLabel(text)
        label.setStyleSheet("font-weight: bold; color: #2E6DA8; margin-top: 4px;")
        return label

    @staticmethod
    def _button(text, tip, signal):
        button = QPushButton(text)
        button.setToolTip(tip)
        button.clicked.connect(lambda _checked=False: signal.emit())
        return button

    def _session_clicked(self):
        (self.logout_requested if self.active else self.login_requested).emit()

    def clear(self):
        self._set_active(False)
        self.user.setText("—")
        self.campus.setText("—")
        self.set_status("espera", "Sin sesión")
        self.set_basemap("espera", "Sin cargar")
        self._edit_text("#ECEFF2", "#40474E", "Inicie sesión para consultar y editar.")
        self.legend.clear()

    def _set_active(self, active):
        self.active = active
        self.session.setText("Cerrar sesión" if active else "Iniciar sesión")
        for widget in (self.selector, self.center, self.all, self.refresh, self.legend):
            widget.setEnabled(active)

    def set_session(self, username, node_code, campus_name):
        self._set_active(True)
        self.user.setText(username)
        self.campus.setText(campus_name)
        self.own_node = node_code
        self.select(node_code)

    def select(self, node_code):
        """Muestra el campus visible; el permiso de edición depende solo de la cuenta."""
        self.selector.setCurrentIndex(self.selector.findData(node_code))
        own = CAMPUS_NAMES[self.own_node]
        if node_code == self.own_node:
            self._edit_text("#DDF1E5", "#14532D", f"✎ Edición autorizada: <b>{own}</b>")
        else:
            self._edit_text("#FFF1D6", "#7A4B00",
                            f"👁 {CAMPUS_NAMES[node_code]}: <b>solo consulta</b>.<br>Edición autorizada: <b>{own}</b>")

    def show_all(self):
        self._edit_text("#DDF1E5", "#14532D",
                        f"Vista de los cinco campus.<br>Edición autorizada: <b>{CAMPUS_NAMES[self.own_node]}</b>")

    def _edit_text(self, background, color, text):
        self.edit.setStyleSheet(f"background: {background}; color: {color};")
        self.edit.setText(text)

    def _state(self, label, state, text):
        color, dot = STATES[state]
        label.setText(f'<span style="color:{color}">{dot}</span> {text}')

    def set_status(self, state, text):
        self._state(self.status, state, text)

    def set_basemap(self, state, text):
        self._state(self.basemap, state, text)

    def set_legend(self, layers, is_visible):
        self.legend.blockSignals(True)
        self.legend.clear()
        for layer in layers:
            item = QTreeWidgetItem([layer.name()])
            item.setData(0, Qt.UserRole, layer.id())
            item.setFlags(item.flags() | Qt.ItemIsUserCheckable)
            item.setCheckState(0, Qt.Checked if is_visible(layer) else Qt.Unchecked)
            entries = [e for e in layer.renderer().legendSymbolItems() if e.symbol() and e.label()]
            icons = [QgsSymbolLayerUtils.symbolPreviewIcon(e.symbol(), QSize(20, 16)) for e in entries]
            if icons:
                item.setIcon(0, icons[0])
            if len(entries) > 1:
                for entry, icon in zip(entries, icons):
                    child = QTreeWidgetItem([entry.label()])
                    child.setIcon(0, icon)
                    child.setFlags(Qt.ItemIsEnabled)
                    item.addChild(child)
            self.legend.addTopLevelItem(item)
        self.legend.blockSignals(False)

    def _toggled(self, item, _column):
        layer_id = item.data(0, Qt.UserRole)
        if layer_id:
            self.layer_toggled.emit(layer_id, item.checkState(0) == Qt.Checked)


class CampusMarkers(QgsMapCanvasItem):
    """Nombre de cada campus cuando el mapa está demasiado alejado para ver sus edificios.

    Es un rótulo del lienzo, no una capa: el grupo conserva exactamente ocho capas.
    """

    MIN_SCALE = 40000

    def __init__(self, canvas, crs, points):
        super().__init__(canvas)
        self.canvas, self.crs, self.points = canvas, crs, points
        self.setZValue(50)
        self.update()

    def boundingRect(self):
        return QRectF(0, 0, self.canvas.width(), self.canvas.height())

    def updatePosition(self):
        self.setPos(QPointF(0, 0))
        self.prepareGeometryChange()

    def visible_names(self):
        return list(self.points) if self.canvas.scale() >= self.MIN_SCALE else []

    def paint(self, painter, _option=None, _widget=None):
        names = self.visible_names()
        if not names:
            return
        transform = QgsCoordinateTransform(self.crs, self.canvas.mapSettings().destinationCrs(),
                                           QgsProject.instance())
        font = QFont(painter.font())
        font.setBold(True)
        font.setPointSize(11)
        painter.setFont(font)
        painter.setRenderHint(painter.Antialiasing)
        for name in names:
            spot = self.toCanvasCoordinates(transform.transform(self.points[name]))
            text = "TEC " + name
            width = painter.fontMetrics().boundingRect(text).width() + 16
            box = QRectF(spot.x() - width / 2, spot.y() - 36, width, 22)
            painter.setPen(QPen(QColor("white"), 1.5))
            painter.setBrush(QColor("#003B73"))
            painter.drawRoundedRect(box, 5, 5)
            painter.drawText(box, Qt.AlignCenter, text)
            painter.setBrush(QColor("#C8102E"))
            painter.drawEllipse(spot, 6, 6)


class Attribution(QObject):
    """Atribución de OpenStreetMap siempre visible en la esquina del mapa."""

    def __init__(self, canvas, text):
        super().__init__(canvas)
        self.canvas = canvas
        self.label = QLabel(text, canvas)
        self.label.setStyleSheet("background: rgba(255,255,255,205); color: #333; padding: 1px 4px; font-size: 10px;")
        self.label.setAttribute(Qt.WA_TransparentForMouseEvents)
        canvas.installEventFilter(self)
        self.place()
        self.label.show()

    def eventFilter(self, _watched, event):
        if event.type() == QEvent.Resize:
            self.place()
        return False

    def place(self):
        self.label.adjustSize()
        self.label.move(max(0, self.canvas.width() - self.label.width() - 2),
                        max(0, self.canvas.height() - self.label.height() - 2))

    def remove(self):
        self.canvas.removeEventFilter(self)
        self.label.deleteLater()
        self.deleteLater()
