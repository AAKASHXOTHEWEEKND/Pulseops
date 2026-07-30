# PulseOps developer/operator entrypoints. `make help` lists targets.
.DEFAULT_GOAL := help
COMPOSE := docker compose
BASE_URL ?= http://localhost:8000

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.PHONY: up
up: ## Build and start the full stack (web/api/worker/db/redis)
	$(COMPOSE) up --build -d

.PHONY: down
down: ## Stop the stack (keep volumes)
	$(COMPOSE) down

.PHONY: clean
clean: ## Stop the stack and delete volumes (data loss)
	$(COMPOSE) down -v

.PHONY: logs
logs: ## Tail logs for all services
	$(COMPOSE) logs -f

.PHONY: ps
ps: ## Show service status
	$(COMPOSE) ps

.PHONY: test
test: ## Run unit tests (in ./app)
	cd app && python -m pytest

.PHONY: lint
lint: ## Lint app code
	cd app && python -m ruff check .

.PHONY: smoke
smoke: ## Run the post-deploy smoke test against BASE_URL
	python scripts/smoke_test.py --base-url $(BASE_URL)

.PHONY: break
break: ## Inject the controlled failure (breaks readiness) and redeploy api
	BREAK_READINESS=true $(COMPOSE) up -d --no-deps api
	@echo "Readiness now broken. Check: curl -i $(BASE_URL)/health/ready"

.PHONY: rollback
rollback: ## Roll back the controlled failure (restore healthy api)
	BREAK_READINESS=false $(COMPOSE) up -d --no-deps api
	@echo "Readiness restored. Verify with: make smoke"

.PHONY: migrate
migrate: ## Run DB migrations only
	$(COMPOSE) run --rm migrate
