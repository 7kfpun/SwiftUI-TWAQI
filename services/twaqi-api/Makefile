# twaqi-api on Cloud Run (FOX-82). Deployed by hand: `make deploy` from this folder.
# One-time setup (service account, secrets, read-only MySQL user): README.md.

PROJECT  ?= kf-personal-tools
REGION   ?= asia-east1
SERVICE  ?= twaqi-api
INSTANCE ?= $(PROJECT):$(REGION):mysql
# The service URL, asked from Cloud Run when a target needs it.
URL      ?= $(shell gcloud --project $(PROJECT) run services describe $(SERVICE) --region $(REGION) --format 'value(status.url)' 2>/dev/null)

GCLOUD = gcloud --project $(PROJECT)

.PHONY: help lint test check run deploy status health logs compare record

help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-10s %s\n", $$1, $$2}'

lint: ## cargo fmt --check + clippy
	cargo fmt --check
	cargo clippy --all-targets -- -D warnings

test: ## Golden + unit + server tests
	cargo test

check: lint test ## Lint and test

run: ## Run locally (DB_* and ORIGIN_TOKEN from the environment)
	cargo run

# Every setting is passed each time, so a deploy always matches this file.
# --allow-unauthenticated: the service checks the Worker's origin token itself.
# --max-instances 3 x DB_CONNECTION_LIMIT=3 caps MySQL at 9 connections (db-f1-micro).
deploy: check ## Test, then build from source and deploy to Cloud Run
	$(GCLOUD) run deploy $(SERVICE) \
	  --region $(REGION) \
	  --source . \
	  --service-account $(SERVICE)@$(PROJECT).iam.gserviceaccount.com \
	  --add-cloudsql-instances $(INSTANCE) \
	  --set-env-vars DB_SOCKET=/cloudsql/$(INSTANCE),DB_USER=twaqi_read,DB_NAME=aqi,DB_CONNECTION_LIMIT=3 \
	  --set-secrets DB_PASSWORD=twaqi-api-db-password:latest,ORIGIN_TOKEN=twaqi-api-origin-token:latest \
	  --allow-unauthenticated \
	  --cpu 1 --memory 512Mi --cpu-boost \
	  --min-instances 0 --max-instances 3 --concurrency 40 --timeout 30
	@$(MAKE) --no-print-directory health

status: ## Latest revisions and the service URL
	$(GCLOUD) run revisions list --service $(SERVICE) --region $(REGION) --limit 3
	@echo "URL: $(URL)"

health: ## /health answers 200 and /v1 refuses without the token
	@curl -fsS $(URL)/health && echo
	@code=$$(curl -s -o /dev/null -w '%{http_code}' $(URL)/v1/countries); \
	  if [ "$$code" = 403 ]; then echo "/v1 without token: 403 (ok)"; \
	  else echo "/v1 without token: $$code (expected 403)"; exit 1; fi

logs: ## Recent service logs
	$(GCLOUD) run services logs read $(SERVICE) --region $(REGION) --limit 50

compare: ## Live Cloud Run vs the Lambda, byte for byte (BASE=... to compare another URL)
	@TWAQI_API_ORIGIN_TOKEN="$$($(GCLOUD) secrets versions access latest --secret twaqi-api-origin-token)" \
	  scripts/compare.sh $(or $(BASE),$(URL))

record: ## Re-record test/fixtures from the live Lambda
	scripts/record.sh
