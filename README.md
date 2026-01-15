# Local Argo stack

This repository contains a local development stack with Argo (CD, Workflows, Events, Rollouts), Crossplane, and Kargo running in a Kind cluster.

## Prerequisites

- [Docker](https://www.docker.com/) or Podman
- [Kind](https://kind.sigs.k8s.io/)
- [cloud-provider-kind](https://github.com/kubernetes-sigs/cloud-provider-kind)
- [Helm](https://helm.sh/)
- [Kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Make](https://www.gnu.org/software/make/) (optional, but recommended)

## Usage

### Quick Start

To spin up the local cluster and install the stack:

```bash
make up
```

This command will:
1. Create a Kind cluster.
2. Install Nginx Ingress.
3. Deploy the Argo stack using the current git repository URL.
4. Update `/etc/hosts` (requires sudo) for local ingress access.

### Clean Up

To destroy the cluster:

```bash
make down
```

## Manual Usage (without Make)

If you prefer to run the script directly:

```bash
chmod +x script.sh
./script.sh "https://github.com/your-repo/argo-stack"
```

The script accepts an optional argument for the repository URL. If not provided, it defaults to `https://github.com/koorikla/argo-stack`.

## Access Points

- **Argo CD**: https://argocd.local (User: `admin`, Password: see script output)
- **Argo Workflows**: http://argo-workflows.local
- **Argo Rollouts**: http://argo-rollouts.local
- **Kargo**: http://kargo.local

## Components

- **Argo CD**: GitOps continuous delivery.
- **Argo Workflows**: Workflow engine.
- **Argo Events**: Event-driven workflow automation.
- **Argo Rollouts**: Advanced deployment strategies.
- **Crossplane**: Infrastructure as Code.
- **Kargo**: Application lifecycle management.

## Development

Lint scripts and charts:

```bash
make lint
```