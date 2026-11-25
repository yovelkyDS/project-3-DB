# Validación del Integrante 3

Fecha de preparación: 24 de noviembre de 2026.

## Ejecutado en este entorno

| Comprobación | Resultado |
|---|---|
| Carga y validación de `config.json` | PASS |
| Contrato de exactamente ocho capas | PASS |
| Rechazo de puerto inaccesible/fuera de rango | PASS |
| Existencia y estructura básica de ocho QML | PASS |
| Catálogo `auth` basado en `session_user`, sin tabla de contraseñas | PASS |
| Firma `layer_styles` compatible con QGIS 3.44 | PASS |
| Compilación sintáctica de Python (`compileall`) | PASS |
| Empaquetado con raíz `sigtec/metadata.txt` | PASS |
| Despliegue de seis nodos PostgreSQL/PostGIS | PASS |
| Replicación y vistas distribuidas sin pérdidas ni duplicados | PASS |
| Cinco cuentas y asignaciones de campus | PASS |
| Rechazo de las cinco contraseñas incorrectas | PASS |
| Exposición de 40 vistas (`8 × 5`) | PASS |
| Ocho estilos institucionales en cada campus | PASS |
| ZIP configurado con los puertos locales efectivos | PASS |
| QGIS 3.44.15 interpreta los colores y tamaños de los ocho QML | PASS |
| QGIS dibuja las ocho capas y centra el mapa en el campus de cada una de las cinco cuentas | PASS |

Comando ejecutado:

```text
python -m unittest discover -s tests/integrante3 -p "test_*.py" -v
Ran 6 tests ... OK
```

El artefacto generado es `dist/sigtec_qgis.zip` e incluye el complemento, configuración y ocho estilos. En esta máquina el rango contractual estaba reservado por Windows, por lo que el paquete usa los puertos efectivos `56430–56435` tomados de `.env` sin incluir credenciales.

La verificación de integración ejecutada fue:

```text
python scripts/distributed/manage.py verify
OK: ocho capas, filas y atributos iguales en ambas rutas; vistas sin perdidas ni duplicados.

python scripts/integrante3/manage.py setup
OK autenticación central: cinco cuentas y asignaciones sincronizadas
OK ocho estilos institucionales guardados en central y distribuidos
OK I3: 5 sesiones, rechazo de claves incorrectas, 40 vistas y 8 estilos por campus
OK complemento instalable: dist\sigtec_qgis.zip
```

## Prueba manual para la demostración

Se verificó el renderizado en QGIS 3.44.15 con un perfil temporal, desde el ZIP y contra los nodos PostgreSQL. Para la demostración, instalar `dist/sigtec_qgis.zip` en QGIS y completar la lista visual del manual, que incluye las cuentas, los estilos, la edición propia y ajena, y la conexión al nodo restaurado.

Para repetir las verificaciones automatizadas con Docker Desktop activo:

```bash
python scripts/distributed/manage.py verify
python scripts/integrante3/manage.py verify
```

Guardar el registro de terminal y las capturas en `evidence/integrante3/` sin incluir `.env` ni contraseñas.
