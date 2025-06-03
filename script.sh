#!/bin/bash

# Exit on any error
set -e

# Define your cluster name
CLUSTER_NAME="kind"

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
        # Try creating the cluster again if the deletion was successful
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
# containerdConfigPatches:
# - |-
#   [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5001"]
#     endpoint = ["http://kind-registry:5001"]
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
    wait_for_pods_ready "kube-system" ""
}

# Wait for pods in specified namespaces to be running and ready (1/1 Ready)
wait_for_pods_ready() {
    local namespace=$1
    local label_selector=$2
    local timeout=${3:-300} # Default timeout 300 seconds
    local interval=${4:-5}  # Default interval 5 seconds

    echo "Waiting for pods in namespace '$namespace' to be 1/1 Ready..."
    local end_time=$(( $(date +%s) + timeout ))
    while true; do
        # Check if all pods are 1/1 Ready
        if ! kubectl get pods -n "$namespace" --selector="$label_selector" | awk '{print $2}' | grep -v "1/1" | grep -v "READY"; then
            current_time=$(date +%s)
            if [[ $current_time -gt $end_time ]]; then
                echo "Timeout waiting for pods in namespace '$namespace' to be 1/1 Ready."
                exit 1
            fi
            echo "Waiting for pods in namespace '$namespace' to be 1/1 Ready..."
            sleep $interval
        else
            echo "Pods in namespace '$namespace' are ready, sleeping 10s to be extra sure. :)"
            sleep 10
            return
        fi
    done
}


get_argocd_admin_password() {
    local max_attempts=50
    local retry_interval=3 # seconds

    for attempt in $(seq 1 $max_attempts); do
        echo "Attempt $attempt of $max_attempts: Retrieving Argo CD admin password..."

        # Try to get the secret
        password=$(kubectl -n argo get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)

        if [ ! -z "$password" ]; then
            echo "Argo CD admin password retrieved successfully."
            echo "Password: $password"
            return
        else
            echo "Secret not found. Waiting for $retry_interval seconds..."
            sleep $retry_interval
        fi
    done

    echo "Failed to retrieve Argo CD admin password after $max_attempts attempts."
    exit 1
}



# Initialize add nginx ingress controller for kind and helm repo
initialize() {
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/kind/deploy.yaml --wait
    sleep 10 # Ingress admissiond controllers take a while to start serving
    helm repo add argo https://argoproj.github.io/argo-helm
    wait_for_pods_ready "ingress-nginx" "app.kubernetes.io/component=controller"
    
}

# Install Argo umbrella Chart and app-of-apps to make it maintain itself in a GitOps manner
install_custom_argo_chart() {
    sleep 10
    helm dependency update helm/argo
    helm upgrade --install argo helm/argo -n argo --set argocd-apps.enabled=false --create-namespace --wait 
    wait_for_pods_ready "argo" ""
    echo "Installing app-of-apps chart to maintain things in a GitOps manner from this point."
    helm upgrade --install argo helm/argo -n argo --set argocd-apps.enabled=true  --wait
}


echo "Creating Kind cluster..."
create_kind_cluster

echo "Initializing ..."
initialize

echo "Installing Argo Umbrella Chart..."
install_custom_argo_chart


echo "####################################################"
echo "----------------------------------------------------"
echo "Setup complete. Argo CD, Argo Workflows, and Argo Events have been installed on your local Kind cluster."


echo "Adding kind ingress entrys to /etc/hosts file"
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
        echo "$entry" | sudo tee -a /etc/hosts > /dev/null
        echo "Added: $entry"
    else
        echo "Already exists: $entry"
    fi
}

# Iterate over the entries and add them if they don't exist
for entry in "${entries[@]}"; do
    add_if_not_exist "$entry"
done
echo "----------------------------------------------------"


echo "open https://argocd.local or http://argo-workflows.local or http://argo-rollouts.local"


echo "Retrieving Argo CD admin password..."
get_argocd_admin_password

