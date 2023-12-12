#!/bin/bash

# Exit on any error
set -e



# Test pushing images via Kaniko to local docker registry, wip

# # Name of the registry container
# REGISTRY_CONTAINER_NAME="kind-registry"

# # Check if the registry container already exists
# if docker container inspect $REGISTRY_CONTAINER_NAME > /dev/null 2>&1; then
#     echo "Container $REGISTRY_CONTAINER_NAME already exists."

#     # Check if the container is not running
#     if [ "$(docker inspect -f '{{.State.Running}}' $REGISTRY_CONTAINER_NAME)" == "false" ]; then
#         echo "Starting the existing container $REGISTRY_CONTAINER_NAME."
#         docker start $REGISTRY_CONTAINER_NAME
#     else
#         echo "Container $REGISTRY_CONTAINER_NAME is already running."
#     fi
# else
#     # Run the registry container
#     echo "Running a new registry container $REGISTRY_CONTAINER_NAME."
#     docker run -d -p 5001:5000 --name $REGISTRY_CONTAINER_NAME --restart=always registry:2
# fi

# # Get the network of your kind cluster
# KIND_CLUSTER_NAME="kind"  # Change if you have a different cluster name
# KIND_NETWORK=$(docker network ls -f name="^${KIND_CLUSTER_NAME}$" -q)

# # Check if the registry is already connected to the kind network
# if ! docker network inspect "${KIND_NETWORK}" --format '{{json .Containers}}' | grep -q "${REGISTRY_CONTAINER_NAME}"; then
#     echo "Connecting the registry container to the kind network."
#     docker network connect "${KIND_NETWORK}" $REGISTRY_CONTAINER_NAME
# else
#     echo "Registry container is already connected to the kind network."
# fi



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
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/kind/deploy.yaml
    helm repo add argo https://argoproj.github.io/argo-helm
    wait_for_pods_ready "ingress-nginx" "app.kubernetes.io/component=controller"
    
}

# Install Argo umbrella Chart and app-of-apps to make it maintain itself in a GitOps manner
install_custom_argo_chart() {
    sleep 10
    helm dependency update helm/argo
    helm upgrade --install argo helm/argo -n argo --create-namespace
    wait_for_pods_ready "argo" ""
    echo "Installing app-of-apps chart to maintain things in a GitOps manner from this point."
    helm dependency update helm/app-of-apps
    helm upgrade --install app-of-apps helm/app-of-apps -n argo
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


echo "Add kind Argo ingress entrys to /etc/hosts file"
echo "----------------------------------------------------"
echo "127.0.0.1       argocd.local"
echo "127.0.0.1       argo-workflows.local"
echo "127.0.0.1       argo-rollouts.local"
echo "127.0.0.1       rollouts-demo.local"
echo "----------------------------------------------------"


echo "open https://argocd.local or http://argo-workflows.local"


echo "Retrieving Argo CD admin password..."
get_argocd_admin_password


# kind delete cluster --name kind

