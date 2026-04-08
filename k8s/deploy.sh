#!/bin/bash
# =============================================================================
# Deployment Script for Video Streaming Platform on Kubernetes
# =============================================================================
# This script builds Docker images and deploys all services to Kubernetes.
#
# Prerequisites:
#   - Docker installed and running
#   - kubectl configured and connected to your cluster
#   - For cloud deployment: docker registry configured (update IMAGE_REGISTRY)
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
# =============================================================================

set -e

# Configuration - Change this to your container registry for cloud deployment
# Examples:
#   GCP:   IMAGE_REGISTRY="gcr.io/your-project-id"
#   AWS:   IMAGE_REGISTRY="123456789.dkr.ecr.us-east-1.amazonaws.com"
#   Azure: IMAGE_REGISTRY="youracr.azurecr.io"
#   Local: IMAGE_REGISTRY="" (for minikube with eval $(minikube docker-env))
IMAGE_REGISTRY=""

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "============================================="
echo "  Deploying Video Streaming Platform to K8s"
echo "============================================="
echo ""

# Step 1: Build Docker images
echo "[1/5] Building Docker images..."
echo "---------------------------------------------"

SERVICES=("auth_service" "file_service" "mysql_service" "upload_service" "stream_service")
K8S_NAMES=("auth-service" "file-service" "mysql-service" "upload-service" "stream-service")

for i in "${!SERVICES[@]}"; do
    svc="${SERVICES[$i]}"
    k8s_name="${K8S_NAMES[$i]}"
    echo "  Building $k8s_name..."
    if [ -z "$IMAGE_REGISTRY" ]; then
        docker build -t "$k8s_name:latest" "$PROJECT_DIR/$svc"
    else
        docker build -t "$IMAGE_REGISTRY/$k8s_name:latest" "$PROJECT_DIR/$svc"
        echo "  Pushing $k8s_name to registry..."
        docker push "$IMAGE_REGISTRY/$k8s_name:latest"
    fi
done
echo "  All images built successfully."
echo ""

# Step 2: Create namespace
echo "[2/5] Creating namespace..."
echo "---------------------------------------------"
kubectl apply -f "$PROJECT_DIR/k8s/namespace.yaml"
echo ""

# Step 3: Deploy configs and secrets
echo "[3/5] Deploying ConfigMaps and Secrets..."
echo "---------------------------------------------"
kubectl apply -f "$PROJECT_DIR/k8s/secrets.yaml"
kubectl apply -f "$PROJECT_DIR/k8s/configmap.yaml"
echo ""

# Step 4: Deploy services (order matters - database first)
echo "[4/5] Deploying services..."
echo "---------------------------------------------"
echo "  Deploying MySQL database..."
kubectl apply -f "$PROJECT_DIR/k8s/mysql-deployment.yaml"

echo "  Waiting for MySQL to be ready..."
kubectl rollout status statefulset/mysql -n video-app --timeout=120s

echo "  Deploying backend services..."
kubectl apply -f "$PROJECT_DIR/k8s/auth-service.yaml"
kubectl apply -f "$PROJECT_DIR/k8s/mysql-api-service.yaml"
kubectl apply -f "$PROJECT_DIR/k8s/file-service.yaml"

echo "  Waiting for backend services..."
kubectl rollout status deployment/auth-service -n video-app --timeout=60s
kubectl rollout status deployment/mysql-service -n video-app --timeout=60s
kubectl rollout status deployment/file-service -n video-app --timeout=60s

echo "  Deploying frontend services..."
kubectl apply -f "$PROJECT_DIR/k8s/upload-service.yaml"
kubectl apply -f "$PROJECT_DIR/k8s/stream-service.yaml"

kubectl rollout status deployment/upload-service -n video-app --timeout=60s
kubectl rollout status deployment/stream-service -n video-app --timeout=60s
echo ""

# Step 5: Deploy HPA
echo "[5/5] Deploying Horizontal Pod Autoscalers..."
echo "---------------------------------------------"
kubectl apply -f "$PROJECT_DIR/k8s/hpa.yaml"
echo ""

# Summary
echo "============================================="
echo "  Deployment Complete!"
echo "============================================="
echo ""
echo "Services:"
kubectl get svc -n video-app
echo ""
echo "Pods:"
kubectl get pods -n video-app
echo ""
echo "HPA Status:"
kubectl get hpa -n video-app
echo ""
echo "---------------------------------------------"
echo "Access the application:"
echo "  Upload Service: kubectl port-forward svc/upload-service 5000:5000 -n video-app"
echo "  Stream Service: kubectl port-forward svc/stream-service 5004:5004 -n video-app"
echo ""
echo "Monitor HPA scaling:"
echo "  kubectl get hpa -n video-app -w"
echo ""
echo "Run load test:"
echo "  ./load-test.sh"
echo "============================================="
