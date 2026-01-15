# Makefile for Argo Stack

CLUSTER_NAME ?= kind
REPO_URL ?= $(shell git config --get remote.origin.url)

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: up
up: ## Create Kind cluster and install Argo stack.
	@echo "Creating cluster and installing stack with Repo URL: $(REPO_URL)"
	@./script.sh "$(REPO_URL)"

.PHONY: down
down: ## Delete the Kind cluster.
	@kind delete cluster --name $(CLUSTER_NAME)

.PHONY: lint
lint: ## Run linters on scripts and Helm charts.
	@echo "Linting scripts..."
	@docker run --rm -v "$$(pwd):/mnt" koalaman/shellcheck:stable script.sh
	@echo "Linting Helm charts..."
	@helm lint helm/argo helm/crossplane helm/kargo

.PHONY: dev
dev: ## Setup development environment (pre-commit).
	@pre-commit install

.PHONY: check
check: ## Run pre-commit hooks on all files.
	@pre-commit run --all-files

##@ Utils

.PHONY: clean
clean: ## Remove temp files.
	@rm -f aws-credentials.txt
