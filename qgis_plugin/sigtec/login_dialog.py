from qgis.PyQt.QtCore import Qt
from qgis.PyQt.QtWidgets import (
    QDialog, QDialogButtonBox, QFormLayout, QLabel, QLineEdit, QVBoxLayout,
)


class LoginDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("SIG-TEC · Iniciar sesión")
        self.setMinimumWidth(380)

        intro = QLabel("Ingrese su cuenta institucional de prueba. El nodo central "
                       "determinará el campus autorizado.")
        intro.setWordWrap(True)
        self.username = QLineEdit()
        self.username.setPlaceholderText("qgis_san_carlos")
        self.password = QLineEdit()
        self.password.setEchoMode(QLineEdit.Password)
        self.password.setPlaceholderText("Contraseña")
        self.password.returnPressed.connect(self.accept)

        form = QFormLayout()
        form.addRow("Usuario:", self.username)
        form.addRow("Contraseña:", self.password)
        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        buttons.button(QDialogButtonBox.Ok).setText("Ingresar")
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)

        layout = QVBoxLayout(self)
        layout.addWidget(intro)
        layout.addLayout(form)
        layout.addWidget(buttons)
        self.username.setFocus(Qt.OtherFocusReason)

    def credentials(self):
        return self.username.text().strip(), self.password.text()
