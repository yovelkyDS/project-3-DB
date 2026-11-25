"""Punto de entrada del complemento SIG-TEC para QGIS."""


def classFactory(iface):
    from .plugin import SigTecPlugin
    return SigTecPlugin(iface)
