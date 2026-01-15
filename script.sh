#!/bin/bash

# Exit on any error
set -e

# Define your cluster name
CLUSTER_NAME="kind"
REPO_URL="${1:-https://github.com/koorikla/argo-stack}"

echo "Using Repository URL: $REPO_URL"

# Function to check if the cluster exists
cluster_exists() {
    kind get clusters | grep -q "^$CLUSTER_NAME\$"
}

# Function to prompt for cluster deletion
prompt_delete_cluster() {
    read -p "Do you want to delete the existing cluster $CLUSTER_NAME? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kind delete cluster --name "$CLUSTER_NAME"
        return 0
    else
        echo "Cluster deletion aborted."
        return 1
    fi
}

# Check if the cluster is running
if cluster_exists; then
    echo "Cluster $CLUSTER_NAME already exists."
    # Prompt the user for a decision to delete the cluster
    if prompt_delete_cluster; then
        echo "Cluster $CLUSTER_NAME has been deleted."
    fi
else
    echo "Creating Kind cluster..."
fi

# Create a Kind cluster
create_kind_cluster() {
    cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"    
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
- role: worker
- role: worker
EOF
    echo "Waiting for the cluster to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s
}

get_argocd_admin_password() {
    echo "Waiting for Argo CD admin secret..."
    kubectl -n argo wait --for=condition=available deployment/argo-cd-server --timeout=300s
    
    local password
    password=$(kubectl -n argo get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
    
    if [ ! -z "$password" ]; then
        echo "Argo CD admin password retrieved successfully."
        echo "Password: $password"
    else
        echo "Failed to retrieve Argo CD admin password yet. Try: kubectl -n argo get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    fi
}

# Initialize add nginx ingress controller for kind and helm repo
initialize() {
    # kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/kind/deploy.yaml
    # echo "Waiting for Ingress Nginx..."
    # kubectl wait --namespace ingress-nginx \
    #   --for=condition=ready pod \
    #   --selector=app.kubernetes.io/component=controller \
    #   --timeout=300s

    helm repo add argo https://argoproj.github.io/argo-helm
}

# Install Argo umbrella Chart and app-of-apps
install_custom_argo_chart() {
    helm dependency update helm/argo
    
    # First install without apps to get CRDs and controllers
    helm upgrade --install argo helm/argo -n argo \
        --set argocd-apps.enabled=false \
        --create-namespace --wait
        
    echo "Installing app-of-apps chart..."
    # Now enable apps, possibly overriding the repo URL
    # We need to find where in values.yaml the repo URL is used. 
    # For now, we are assuming the user relies on the sed command or we pass it as a value.
    # To truly support dynamic repo URL without sed, we should expose it as a value in the chart or use a values file override.
    # Since the values.yaml structure is complex (multiple apps), passing one --set might not be enough if it's used in multiple places.
    # But for the requested improvement, let's at least inject it into the main 'intra' project source if possible.
    
    # NOTE: To FULLY support dynamic REPO_URL without editing values.yaml, the helm chart values need to templated or we need to pass overrides for each app.
    # The README said: "Change all 'https://github.com/koorikla/argo-stack' for your repo in helm/argo/values.yaml"
    # So we will do a temporary sed on a copy or just rely on the user having done it if they aren't using the default.
    # OR better: We use `sed` here in the script on a temporary file to avoid modifying the git tracked file? 
    # Or we accept that `make up` might modify the file if we want to automate it. 
    # Let's stick to the plan: "Replace the sed command in the README with a dynamic Makefile approach"
    # Actually, modifying the file in place is what the original README did. 
    # Let's try to pass it via --set if we can find a common variable, but the values.yaml has it hardcoded in many places.
    # A cleaner way is to use `sed` but on a temporary values file generated from the main one.
    
    cp helm/argo/values.yaml helm/argo/values.temp.yaml
    sed -i '' "s|https://github.com/koorikla/argo-stack|$REPO_URL|g" helm/argo/values.temp.yaml
    
    helm upgrade --install argo helm/argo -n argo \
        --set argocd-apps.enabled=true \
        --values helm/argo/values.temp.yaml \
        --wait
        
    rm helm/argo/values.temp.yaml
}

echo "Creating Kind cluster..."
if ! cluster_exists; then
   create_kind_cluster
fi

echo "Initializing ..."
initialize

echo "Installing Argo Umbrella Chart..."
install_custom_argo_chart

echo "####################################################"
echo "----------------------------------------------------"
echo "Setup complete. Argo CD, Argo Workflows, and Argo Events have been installed."

echo "Adding kind ingress entries to /etc/hosts file"
echo "----------------------------------------------------"
# Define the entries to add
entries=(
    "127.0.0.1       argocd.local"
    "127.0.0.1       argo-workflows.local"
    "127.0.0.1       argo-rollouts.local"
    "127.0.0.1       rollouts-demo.local"
    "127.0.0.1       kargo.local"
)

# Function to add an entry if it doesn't exist
add_if_not_exist() {
    local entry=$1
    if ! grep -qF -- "$entry" /etc/hosts; then
        echo "Need sudo to add '$entry' to /etc/hosts"
        echo "$entry" | sudo tee -a /etc/hosts > /dev/null
        echo "Added: $entry"
    else
        echo "Already exists: $entry"
    fi
}

for entry in "${entries[@]}"; do
    add_if_not_exist "$entry"
done
echo "----------------------------------------------------"


echo "Access ArgoCD: https://argocd.local"
echo "Access Workflows: http://argo-workflows.local"
echo "Access Rollouts: http://argo-rollouts.local"
echo "Access Kargo: http://kargo.local (password: kargo)"


echo "Retrieving Argo CD admin password..."
echo "username: admin"
get_argocd_admin_password
