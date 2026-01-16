# Makefile for Argo Stack

CLUSTER_NAME ?= kind
REPO_URL ?= $(shell git config --get remote.origin.url)

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: up
up: ## Create cluster and install everything.
	@$(MAKE) cloud-provider
	@$(MAKE) create-cluster
	@$(MAKE) init
	@$(MAKE) install
	@$(MAKE) hosts
	@echo "----------------------------------------------------"
	@echo "Setup complete!"
	@echo "Access ArgoCD: https://argocd.local"
	@echo "Access Workflows: http://argo-workflows.local"
	@echo "Access Rollouts: http://argo-rollouts.local"
	@echo "Access Kargo: http://kargo.local (password: kargo)"
	@echo "----------------------------------------------------"
	@$(MAKE) password

.PHONY: create-cluster
create-cluster: ## Create Kind cluster.
	@if kind get clusters | grep -q "^$(CLUSTER_NAME)$$"; then \
		echo "Cluster $(CLUSTER_NAME) already exists."; \
	else \
		echo "Creating Kind cluster..."; \
		printf '%s\n' \
			'kind: Cluster' \
			'apiVersion: kind.x-k8s.io/v1alpha4' \
			'nodes:' \
			'- role: control-plane' \
			'- role: worker' \
			'- role: worker' \
			| kind create cluster --config=-; \
		echo "Waiting for nodes..."; \
		kubectl wait --for=condition=Ready nodes --all --timeout=300s; \
	fi

.PHONY: cloud-provider
cloud-provider: ## Start cloud-provider-kind in a new terminal.
	@echo "Checking cloud-provider-kind..."
	@if pgrep -f cloud-provider-kind > /dev/null; then \
		echo "Killing existing cloud-provider-kind..."; \
		sudo pkill -f cloud-provider-kind || true; \
	fi
	@echo "Starting cloud-provider-kind in a new Terminal window..."
	@osascript -e 'tell app "Terminal" to do script "echo Starting cloud-provider-kind...; sudo cloud-provider-kind"'; \
	osascript -e 'tell app "Terminal" to activate'

.PHONY: init
init: ## Initialize Helm repos and dependencies.
	@echo "Initializing..."
	@echo "Installing Envoy Gateway..."
	@helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
		--version v1.2.3 \
		-n envoy-gateway-system \
		--create-namespace --wait \
		--skip-crds

	@echo "Waiting for Gateway CRD to be installed..."
	@kubectl wait --for condition=established --timeout=300s crd/gateways.gateway.networking.k8s.io
	@kubectl create namespace argo --dry-run=client -o yaml | kubectl apply -f -

	@echo "Applying Gateway API resources..."
	@kubectl apply -f manifests/gateway.yaml
# 	@kubectl apply -f manifests/httproute-kargo.yaml

	@echo "Waiting for Gateway to be ready..."
	@kubectl wait --namespace argo \
		--for=condition=Programmed gateway/external \
		--timeout=300s

	@helm repo add argo https://argoproj.github.io/argo-helm
	@helm repo update

.PHONY: hosts
hosts: ## Update /etc/hosts with LoadBalancer IP.
	@echo "Getting Gateway IP..."
	@# Wait for Gateway to have an IP
	@echo "Waiting for Gateway IP..."
	@sleep 5
	@IP=$$(kubectl get gateway external -n argo -o jsonpath='{.status.addresses[0].value}'); \
	if [ -z "$$IP" ]; then \
		echo "Error: Could not get Gateway IP. Is cloud-provider-kind running?"; \
		exit 1; \
	else \
		echo "Gateway IP: $$IP"; \
		echo "Updating /etc/hosts (requires sudo)..."; \
		for domain in argocd.local argo-workflows.local argo-rollouts.local kargo.local; do \
			echo "Updating $$domain to $$IP..."; \
			sudo sed -i '' "/[[:space:]]$$domain$$/d" /etc/hosts; \
			echo "$$IP $$domain" | sudo tee -a /etc/hosts; \
		done \
	fi

.PHONY: install
install: ## Install Argo stack.
	@echo "Installing Argo Stack..."
	@helm dependency update helm/argo
	@# First install without apps to get CRDs
	@helm upgrade --install argo helm/argo -n argo \
		--set argocd-apps.enabled=false \
		--create-namespace --wait
	@echo "Installing Argo Apps..."
	@# Generate temp values with dynamic repo URL
	@cp helm/argo/values.yaml helm/argo/values.temp.yaml
	@sed -i '' "s|https://github.com/koorikla/argo-stack|$(REPO_URL)|g" helm/argo/values.temp.yaml
	@helm upgrade --install argo helm/argo -n argo \
		--set argocd-apps.enabled=true \
		--values helm/argo/values.temp.yaml \
		--wait
	@rm helm/argo/values.temp.yaml

.PHONY: password
password: ## Retrieve Argo CD admin password.
	@echo "Waiting for Argo CD admin secret..."
	@kubectl -n argo wait --for=condition=available deployment/argo-cd-server --timeout=300s
	@echo "Argo CD Admin Password:"
	@kubectl -n argo get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo ""

.PHONY: down
down: ## Delete the Kind cluster.
	@kind delete cluster --name $(CLUSTER_NAME)

.PHONY: lint
lint: ## Run linters on Helm charts.
	@echo "Linting Helm charts..."
	@helm lint helm/argo helm/crossplane helm/kargo

##@ Utils

.PHONY: dev
dev: ## Setup development environment (pre-commit).
	@pip3 install pre-commit
	@pre-commit install

.PHONY: check
check: ## Run pre-commit hooks on all files.
	@pre-commit run --all-files

.PHONY: clean
clean: ## Remove temp files.
	@rm -f aws-credentials.txt helm/argo/values.temp.yaml
