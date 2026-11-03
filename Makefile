# Common tasks. `make help` lists them.
.DEFAULT_GOAL := help
SHELL := /bin/bash
CHART := deploy/helm/matterhub

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.PHONY: install
install: ## Install app + dev dependencies into the active virtualenv
	cd app && pip install --require-hashes --no-deps -r requirements.txt && pip install -r requirements-dev.txt && pip install --no-deps -e .

.PHONY: test
test: ## Lint, type-check and test the app
	cd app && ruff check . && ruff format --check . && mypy && pytest --cov

.PHONY: run
run: ## Run the API locally with SQLite and auth disabled
	cd app && MATTERHUB_AUTH_MODE=disabled matterhub migrate && MATTERHUB_AUTH_MODE=disabled matterhub serve

.PHONY: up
up: ## Start the docker compose stack (API, Postgres, Prometheus, Grafana)
	docker compose up --build -d && docker compose ps

.PHONY: down
down: ## Stop the compose stack and delete its data
	docker compose down -v

.PHONY: image
image: ## Build the container image
	docker build -t matterhub:local --build-arg GIT_SHA=$$(git rev-parse --short HEAD) app

.PHONY: scan
scan: image ## Scan the image with Trivy
	trivy image --severity HIGH,CRITICAL --ignore-unfixed matterhub:local

.PHONY: kind-up
kind-up: ## Deploy the Helm chart to a local kind cluster
	./scripts/kind-up.sh

.PHONY: kind-down
kind-down: ## Delete the local kind cluster
	./scripts/kind-down.sh

.PHONY: helm-check
helm-check: ## Lint and schema-validate the Helm chart for every environment
	helm lint --strict $(CHART) -f $(CHART)/ci/test-values.yaml
	for env in dev prod; do helm template matterhub $(CHART) -n matterhub -f $(CHART)/values-$$env.yaml -f $(CHART)/ci/test-values.yaml | kubeconform -strict -summary -ignore-missing-schemas; done

.PHONY: tf-check
tf-check: ## terraform fmt + validate both environments
	terraform fmt -check -recursive infra/terraform
	for env in dev prod; do terraform -chdir=infra/terraform/envs/$$env init -backend=false -input=false >/dev/null && terraform -chdir=infra/terraform/envs/$$env validate; done

.PHONY: bicep-check
bicep-check: ## Lint and build the Bicep foundation
	az bicep lint --file infra/bicep/main.bicep && az bicep build --file infra/bicep/main.bicep --stdout >/dev/null

.PHONY: policy
policy: ## Run Checkov over all IaC
	checkov --config-file .checkov.yaml -d infra --framework terraform arm bicep

.PHONY: scripts-check
scripts-check: ## shellcheck, PSScriptAnalyzer, Pester and Python script tests
	shellcheck scripts/*.sh
	pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path scripts/powershell -Recurse -Settings scripts/powershell/PSScriptAnalyzerSettings.psd1 -EnableExit"
	pwsh -NoProfile -Command "Invoke-Pester -Path scripts/powershell/tests -CI"
	pytest -q scripts/python/tests

.PHONY: check
check: test helm-check tf-check bicep-check scripts-check policy ## Everything CI runs (needs all the tools)

.PHONY: release-notes
release-notes: ## Release notes since the last tag
	python scripts/python/release_notes.py $$(git describe --tags --abbrev=0) HEAD
