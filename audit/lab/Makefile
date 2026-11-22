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
        recovery-stop recovery-clean psql versions clean

help: ## Muestra esta ayuda
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo "  Variables: NODE=all|campus|central|cartago|san_jose|san_carlos|alajuela|limon"

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

migrate: ## Aplica migraciones pendientes (NODE=...)
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
	@scripts/backup/wal_retention.sh $(NODE) --keep $${KEEP:-2} $(if $(APPLY),--apply,)

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
