# SIG-TEC

Proyecto de Bases de Datos II para consultar y editar información geográfica de los cinco campus del Tecnológico de Costa Rica. Un nodo central autentica a los usuarios y consolida los datos de los cinco nodos de campus mediante replicación lógica.

El complemento de QGIS muestra ocho capas geográficas y permite editar los objetos del campus de la cuenta. Los seis nodos usan PostgreSQL 17.12 y PostGIS 3.5.4 en Docker. El proyecto también incluye respaldos y recuperación a un punto en el tiempo (PITR).

## Requisitos

- Docker con Compose v2.20 o posterior. En Windows y macOS, abre Docker Desktop antes de empezar.
- Python 3.10 o posterior y QGIS 3.44 LTR. El complemento se probó con QGIS 3.44.15.
- En Windows, PowerShell y Git Bash. En Linux y macOS, Bash y `make`.

## Primera instalación

Ejecuta los comandos desde la raíz del repositorio. Si ya tienes volúmenes de una instalación anterior y quieres reutilizarlos, copia primero su `.env` al clon actual. PostgreSQL conserva en esos volúmenes la contraseña con la que se inicializó.

Para instalar en paralelo, usa un clon aparte. Allí, copia `.env.example` a `.env` y configura un `COMPOSE_PROJECT_NAME` distinto y puertos disponibles antes de arrancar.

### Windows (PowerShell)

Ejecuta una línea a la vez y continúa cuando el paso anterior termine correctamente.

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
python scripts\distributed\manage.py setup
python scripts\datos\importar.py
python scripts\integrante3\manage.py setup
```

El importador invoca `bash` para respaldar los datos iniciales. Si `bash` falta en el `PATH` o apunta a WSL, antepón Git Bash con `$env:Path = "C:\Program Files\Git\bin;$env:Path"` antes de importar. Ajusta la ruta si instalaste Git en otra carpeta.

### Linux y macOS

```bash
make install
```

La instalación levanta seis nodos, configura la replicación, importa la geografía, instala las cuentas y los estilos, y genera `dist/sigtec_qgis.zip`. El primer arranque puede tardar varios minutos mientras se construye la imagen de PostGIS.

## Abrir el proyecto en QGIS

1. En **Complementos → Administrar e instalar complementos → Instalar a partir de ZIP**, selecciona `dist/sigtec_qgis.zip` y activa **SIG-TEC**.
2. Pulsa el ícono azul con un pin rojo junto al de Python, o usa **Database → SIG-TEC → Iniciar sesión en SIG-TEC**.
3. Entra con una cuenta de campus, por ejemplo `qgis_san_carlos`. Su contraseña es el valor de `SIGTEC_QGIS_SAN_CARLOS_PASSWORD` en el `.env` local. Si QGIS solicita una contraseña maestra, usa la de su almacén de credenciales.
4. Comprueba que aparezcan el panel **SIG-TEC**, las ocho capas y el mapa base de OpenStreetMap. **Todos los campus** muestra la vista general. El selector cambia el encuadre y tu cuenta determina qué objetos puedes editar.

La geografía proviene de [OpenStreetMap](https://www.openstreetmap.org/copyright) (ODbL). La iluminación y casi toda la accesibilidad son datos sintéticos de demostración. [Fuentes y cobertura](docs/DATOS_GEOGRAFICOS.md)

## Volver a abrir y verificar

- `docker compose up -d` inicia el entorno existente. `docker compose ps` muestra el estado de los seis nodos y `docker compose stop` los detiene conservando los datos.
- En Windows, `python scripts\integrante3\manage.py verify` comprueba cuentas, vistas y estilos. En Linux y macOS, usa `make integrante3-verify`.
- Para actualizar el complemento, regenera el ZIP con `python scripts\integrante3\manage.py package` en Windows o `make qgis-plugin` en Linux y macOS. Instala de nuevo el ZIP en QGIS. Si cambiaste los puertos en `.env`, aplica primero el cambio con `docker compose up -d`.

## Documentación

- [Arquitectura, red y puertos](docs/ARCHITECTURE.md) y [modelo geográfico](docs/DATA_DICTIONARY.md).
- [Respaldos y recuperación](docs/BACKUP_RECOVERY.md).

