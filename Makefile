# =====================================================================
# SIG-TEC · comandos de operación (Integrante 1)
#   make help   lista los comandos
# Requiere: bash, Docker + Compose v2. Todo lo demás corre en contenedores.
# =====================================================================
SHELL := /bin/bash
.DEFAULT_GOAL := help

COMPOSE := docker compose --project-directory . -f compose.yaml
TOOLS   := $(COMPOSE) --profile tools run --rm -T sigtec-tools
NODES   := pg-central pg-cartago pg-san-jose pg-san-carlos pg-alajuela pg-limon
NODE    ?= all

.PHONY: help prereqs setup build up down restart status ps logs migrate seed verify \
        test test-full backup backup-logical backup-physical backup-list restore-test \
        restore-logical-test restore-physical-test wal-retention pitr-demo recovery-status \
        recovery-stop recovery-clean psql versions clean integrante3-setup integrante3-verify \
        integrante3-unit qgis-plugin qgis-test install test-all datos-reales

# Entorno completo de los tres integrantes
install: ## Entorno completo: nodos, datos, replicación, cuentas, estilos y ZIP de QGIS
	@$(MAKE) setup
	@$(MAKE) replication-setup
	@$(MAKE) datos-reales
	@$(MAKE) integrante3-setup

test-all: ## Todas las pruebas: unitarias, SQL, replicación, permisos, 2PC, cuentas y QGIS
	@$(MAKE) distributed-unit
	@$(MAKE) integrante3-unit
	@$(MAKE) test
	@$(MAKE) distributed-test
	@$(MAKE) integrante3-verify
	@$(MAKE) qgis-test

datos-reales: ## Sustituye los datos sintéticos por la geografía real (OSM), con respaldo previo; idempotente
	@$(PYTHON) scripts/datos/importar.py

qgis-test: qgis-plugin ## Prueba el complemento con PyQGIS real y perfil temporal (requiere QGIS 3.44 LTR)
	@py="$$(scripts/qgis_python.sh)" && "$$py" tests/integrante3/qgis_integration.py </dev/null

help: ## Muestra esta ayuda
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo "  Variables: NODE=all|campus|central|cartago|san_jose|san_carlos|alajuela|limon  (migrate/verify: también NODE=recovery)"

prereqs: ## Comprueba requisitos del host (e inicia Docker si está detenido)
	@scripts/check_prereqs.sh --start-docker

setup: ## Instala/actualiza todo desde cero (idempotente, no destruye datos)
	@scripts/setup.sh

build: ## Construye la imagen PostgreSQL 17.12 + PostGIS 3.5.4
	@$(COMPOSE) build pg-central

up: ## Inicia los seis nodos
	@$(COMPOSE) up -d $(NODES)

down: ## Detiene los nodos (conserva volúmenes y datos)
	@$(COMPOSE) --profile recovery stop
	@$(COMPOSE) --profile recovery down

restart: ## Reinicia los seis nodos
	@$(COMPOSE) restart $(NODES)

status: ## Estado de contenedores y verificación rápida de los nodos
	@$(COMPOSE) --profile recovery ps
	@$(TOOLS) scripts/db/verify.sh $(NODE)

ps: ## Estado de los contenedores
	@$(COMPOSE) --profile recovery ps

logs: ## Logs (NODE=<nodo> para uno solo)
	@if [ "$(NODE)" = all ]; then $(COMPOSE) logs --tail=100 $(NODES); \
	 else $(COMPOSE) logs --tail=200 pg-$$(echo $(NODE) | tr _ -); fi

migrate: ## Aplica migraciones pendientes (NODE=...; NODE=recovery para la instancia recuperada)
	@$(TOOLS) scripts/db/migrate.sh $(NODE)

seed: ## Carga datos de prueba si faltan (idempotente)
	@$(TOOLS) scripts/db/seed.sh $(if $(filter all,$(NODE)),campus,$(NODE))

verify: ## Validación de versiones, PostGIS y capas (NODE=..., o NODE=recovery)
	@$(TOOLS) scripts/db/verify.sh $(NODE)

test: ## Pruebas automatizadas (infraestructura, modelo, identificadores, repo)
	@tests/run_tests.sh

test-full: ## Pruebas + idempotencia + persistencia tras reinicio
	@tests/run_tests.sh --full

backup: backup-logical backup-physical ## Respaldo lógico y físico de NODE (por omisión, los seis)

backup-logical: ## pg_dump de NODE (formato custom + globales + manifiesto)
	@scripts/backup/run.sh logical_backup.sh $(NODE)

backup-physical: ## pg_basebackup de NODE (+ pg_verifybackup)
	@scripts/backup/run.sh physical_backup.sh $(NODE)

backup-list: ## Lista los respaldos y el WAL archivado
	@$(TOOLS) scripts/backup/list_backups.sh

restore-test: restore-logical-test restore-physical-test ## Prueba ambas restauraciones en entornos aislados

restore-logical-test: ## Restaura el último pg_dump de NODE en un clúster temporal y lo valida
	@scripts/backup/run.sh logical_restore_test.sh $(NODE)

restore-physical-test: ## Recupera el último pg_basebackup + WAL de NODE en un clúster temporal
	@scripts/backup/run.sh physical_restore_test.sh $(NODE)

wal-retention: ## Muestra qué WAL archivado se podría depurar (KEEP=2 respaldos; APPLY=1 para borrar)
	@case "$(APPLY)" in \
	   ""|0) a="" ;; \
	   1) a="--apply" ;; \
	   *) echo "APPLY debe ser 1 (eliminar) o 0/vacío (simulación); recibido: $(APPLY)" >&2; exit 2 ;; \
	 esac; \
	 scripts/backup/wal_retention.sh $(NODE) --keep $${KEEP:-2} $$a

pitr-demo: ## Demostración de falla + PITR en instancia aislada (NODE=san_carlos)
	@scripts/recovery/pitr_demo.sh $(if $(filter all,$(NODE)),san_carlos,$(NODE))

recovery-status: ## Estado y verificación de la instancia recuperada pg-recovery
	@$(COMPOSE) --profile recovery ps pg-recovery
	@$(TOOLS) scripts/db/verify.sh recovery

recovery-stop: ## Detiene pg-recovery (conserva su volumen)
	@$(COMPOSE) --profile recovery stop pg-recovery

recovery-clean: ## ELIMINA la instancia recuperada y su volumen (pide confirmación)
	@scripts/clean.sh --recovery-only

psql: ## Consola psql en NODE (superusuario; NODE=cartago, recovery, ...)
	@n=$(NODE); [ "$$n" = all ] && n=central; \
	 if [ "$$n" = recovery ]; then svc=pg-recovery; else svc=pg-$$(echo $$n | tr _ -); fi; \
	 $(COMPOSE) --profile recovery exec -u postgres $$svc psql -d sigtec

versions: ## Registra versiones efectivas en evidence/versions.txt
	@scripts/versions.sh

clean: ## ELIMINA contenedores y TODOS los volúmenes del proyecto (pide confirmación)
	@scripts/clean.sh

# Integrante 2 (Python 3.10+ en el host)
# Primer intérprete >= 3.10 disponible (macOS/Linux suelen traer solo python3; Windows, python).
PYTHON ?= $(shell for p in python3 python; do "$$p" -c 'import sys; sys.exit(sys.version_info < (3, 10))' >/dev/null 2>&1 && { echo "$$p"; exit 0; }; done; echo python3)
.PHONY: replication-setup replication-verify distributed-test distributed-unit distributed-resolve
replication-setup: ## Instala replicación y vistas del integrante 2
	@$(PYTHON) scripts/distributed/manage.py setup
replication-verify: ## Compara filas de originales, central y copias
	@$(PYTHON) scripts/distributed/manage.py verify
distributed-test: ## CRUD, permisos, propagación y 2PC (requiere nodos activos)
	@$(PYTHON) tests/distributed/integration.py
distributed-unit: ## Pruebas locales del coordinador sin Docker
	@$(PYTHON) -m unittest discover -s tests/distributed -p 'test_*.py' -v
distributed-resolve: ## Resuelve decisiones durables 2PC pendientes
	@$(PYTHON) scripts/distributed/manage.py resolve

# Integrante 3 (autenticación central, complemento QGIS y estilos)
integrante3-setup: ## Instala autenticación/estilos, verifica y empaqueta el complemento
	@$(PYTHON) scripts/integrante3/manage.py setup

integrante3-verify: ## Prueba 5 cuentas, rechazo de claves, vistas y estilos replicados
	@$(PYTHON) scripts/integrante3/manage.py verify

integrante3-unit: ## Pruebas locales del complemento sin requerir QGIS ni Docker
	@$(PYTHON) -m unittest discover -s tests/integrante3 -p 'test_*.py' -v

qgis-plugin: ## Genera dist/sigtec_qgis.zip listo para instalar en QGIS
	@$(PYTHON) scripts/integrante3/manage.py package
