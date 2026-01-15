# Local Argo stack

This repository contains a local development stack with Argo (CD, Workflows, Events, Rollouts), Crossplane, and Kargo running in a Kind cluster.

## Prerequisites

Install the required tools on macOS using Homebrew:

```bash
brew install --cask docker
brew install kind helm kubectl
```

For `cloud-provider-kind`:
```bash
brew install cloud-provider-kind
```
*Alternatively, you can install via Go:*
```bash
go install sigs.k8s.io/cloud-provider-kind@latest
```

## Usage

### Quick Start

1. Start `cloud-provider-kind` in a separate terminal:
   ```bash
   cloud-provider-kind
   ```
2. Spin up the stack:
   ```bash
   make up
   ```

This will:
1. Create a Kind cluster.
2. Install the Argo stack (Argo CD, Workflows, Events, Rollouts, Kargo, Crossplane).
3. Retrieve the initial admin password.

### Clean Up

To destroy the cluster:

```bash
make down
```

## Access Points

*Note: The `make up` command will automatically prompt to update your `/etc/hosts` to point these domains to the correct LoadBalancer IP.*

- **Argo CD**: https://argocd.local (User: `admin`, Password: see output)
- **Argo Workflows**: http://argo-workflows.local
- **Argo Rollouts**: http://argo-rollouts.local
- **Kargo**: http://kargo.local

## Development

- **Lint scripts and charts**: `make lint`
- **Install pre-commit hooks**: `make dev`
- **Run all checks**: `make check`
