#!/bin/bash

# Exit on any error
set -e

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
    wait_for_pods_ready "kube-system" ""
}

# Wait for pods in specified namespaces to be running
wait_for_pods_ready() {
    local namespace=$1
    local label_selector=$2
    local timeout=${3:-300} # Default timeout 300 seconds
    local interval=${4:-5}  # Default interval 5 seconds

    echo "Waiting for pods in namespace '$namespace' to be ready..."
    local end_time=$(( $(date +%s) + timeout ))
    while true; do
        if ! kubectl get pods -n "$namespace" --selector="$label_selector" | grep -q 'Running'; then
            current_time=$(date +%s)
            if [[ $current_time -gt $end_time ]]; then
                echo "Timeout waiting for pods in namespace '$namespace' to be ready."
                exit 1
            fi
            echo "Waiting for pods in namespace '$namespace' to be ready..."
            sleep $interval
        else
            sleep 10
            echo "Pods in namespace '$namespace' are ready."
            return
        fi
    done
}


get_argocd_admin_password() {
    local max_attempts=5
    local retry_interval=10 # seconds

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
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/kind/deploy.yaml
    helm repo add argo https://argoproj.github.io/argo-helm
    wait_for_pods_ready "ingress-nginx" "app.kubernetes.io/component=controller"
    echo "sleeping 10 sec to ensure the ingress controller's wbhook is ready"
}

# Install Custom Argo Chart
install_custom_argo_chart() {
    # Assuming my-argo-chart is in the current directory
    helm dependency update helm/argo
    helm upgrade --install argo helm/argo -n argo --create-namespace
    wait_for_pods_ready "argo" ""
}


echo "Creating Kind cluster..."
create_kind_cluster

echo "Initializing ..."
initialize

echo "Installing Custom Argo Chart..."
install_custom_argo_chart



echo "----------------------------------------------------"
echo "Setup complete. Argo CD, Argo Workflows, and Argo Events have been installed on your local Kind cluster."


echo "Add kind Argo ingress entrys to /etc/hosts file"
echo "----------------------------------------------------"
echo "127.0.0.1       argocd.local"
echo "127.0.0.1       argo-workflows.local"
echo "----------------------------------------------------"


echo "open http://argocd-server.local or http://argo-workflows.local, login with admin and password:"

echo "Retrieving Argo CD admin password..."
get_argocd_admin_password


# kind delete cluster --name kind

