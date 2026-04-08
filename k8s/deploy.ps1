# =============================================================================
# Deployment Script for Video Streaming Platform on Kubernetes (PowerShell)
# =============================================================================
# This script builds Docker images and deploys all services to Kubernetes.
#
# Prerequisites:
#   - Docker installed and running
#   - kubectl configured and connected to your cluster
#   - For cloud deployment: docker registry configured (update $IMAGE_REGISTRY)
#
# Usage:
#   .\deploy.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

# Configuration - Change this to your container registry for cloud deployment
$IMAGE_REGISTRY = ""

$PROJECT_DIR = (Resolve-Path "$PSScriptRoot\..").Path

Write-Host "============================================="
Write-Host "  Deploying Video Streaming Platform to K8s"
Write-Host "============================================="
Write-Host ""

# Step 1: Build Docker images
Write-Host "[1/5] Building Docker images..."
Write-Host "---------------------------------------------"

$SERVICES = @("auth_service", "file_service", "mysql_service", "upload_service", "stream_service")
$K8S_NAMES = @("auth-service", "file-service", "mysql-service", "upload-service", "stream-service")

for ($i = 0; $i -lt $SERVICES.Length; $i++) {
    $svc = $SERVICES[$i]
    $k8s_name = $K8S_NAMES[$i]
    Write-Host "  Building $k8s_name..."
    if ([string]::IsNullOrEmpty($IMAGE_REGISTRY)) {
        docker build -t "${k8s_name}:latest" "$PROJECT_DIR\$svc"
    } else {
        docker build -t "${IMAGE_REGISTRY}/${k8s_name}:latest" "$PROJECT_DIR\$svc"
        Write-Host "  Pushing $k8s_name to registry..."
        docker push "${IMAGE_REGISTRY}/${k8s_name}:latest"
    }
    if ($LASTEXITCODE -ne 0) { throw "Failed to build $k8s_name" }
}
Write-Host "  All images built successfully."
Write-Host ""

# Step 2: Create namespace
Write-Host "[2/5] Creating namespace..."
Write-Host "---------------------------------------------"
kubectl apply -f "$PROJECT_DIR\k8s\namespace.yaml"
if ($LASTEXITCODE -ne 0) { throw "Failed to create namespace" }
Write-Host ""

# Step 3: Deploy configs and secrets
Write-Host "[3/5] Deploying ConfigMaps and Secrets..."
Write-Host "---------------------------------------------"
kubectl apply -f "$PROJECT_DIR\k8s\secrets.yaml"
kubectl apply -f "$PROJECT_DIR\k8s\configmap.yaml"
if ($LASTEXITCODE -ne 0) { throw "Failed to deploy configs" }
Write-Host ""

# Step 4: Deploy services (order matters - database first)
Write-Host "[4/5] Deploying services..."
Write-Host "---------------------------------------------"
Write-Host "  Deploying MySQL database..."
kubectl apply -f "$PROJECT_DIR\k8s\mysql-deployment.yaml"

Write-Host "  Waiting for MySQL to be ready..."
kubectl rollout status statefulset/mysql -n video-app --timeout=120s

Write-Host "  Deploying backend services..."
kubectl apply -f "$PROJECT_DIR\k8s\auth-service.yaml"
kubectl apply -f "$PROJECT_DIR\k8s\mysql-api-service.yaml"
kubectl apply -f "$PROJECT_DIR\k8s\file-service.yaml"

Write-Host "  Waiting for backend services..."
kubectl rollout status deployment/auth-service -n video-app --timeout=60s
kubectl rollout status deployment/mysql-service -n video-app --timeout=60s
kubectl rollout status deployment/file-service -n video-app --timeout=60s

Write-Host "  Deploying frontend services..."
kubectl apply -f "$PROJECT_DIR\k8s\upload-service.yaml"
kubectl apply -f "$PROJECT_DIR\k8s\stream-service.yaml"

kubectl rollout status deployment/upload-service -n video-app --timeout=60s
kubectl rollout status deployment/stream-service -n video-app --timeout=60s
Write-Host ""

# Step 5.5: Fetch external LoadBalancer DNS and patch configmap
Write-Host "[5.5/6] Fetching external LoadBalancer DNS..."
Write-Host "---------------------------------------------"

Write-Host "  Waiting for upload-service LoadBalancer DNS..."
$UPLOAD_DNS = ""
for ($i = 1; $i -le 60; $i++) {
    $UPLOAD_DNS = kubectl get svc upload-service -n video-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
    if (-not [string]::IsNullOrEmpty($UPLOAD_DNS)) { break }
    Start-Sleep -Seconds 5
}
if ([string]::IsNullOrEmpty($UPLOAD_DNS)) {
    Write-Host "  WARNING: Could not get upload-service external DNS after 5 minutes"
} else {
    Write-Host "  Upload Service DNS: $UPLOAD_DNS"
}

Write-Host "  Waiting for stream-service LoadBalancer DNS..."
$STREAM_DNS = ""
for ($i = 1; $i -le 60; $i++) {
    $STREAM_DNS = kubectl get svc stream-service -n video-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
    if (-not [string]::IsNullOrEmpty($STREAM_DNS)) { break }
    Start-Sleep -Seconds 5
}
if ([string]::IsNullOrEmpty($STREAM_DNS)) {
    Write-Host "  WARNING: Could not get stream-service external DNS after 5 minutes"
} else {
    Write-Host "  Stream Service DNS: $STREAM_DNS"
}

if (-not [string]::IsNullOrEmpty($UPLOAD_DNS) -and -not [string]::IsNullOrEmpty($STREAM_DNS)) {
    Write-Host "  Patching configmap with external URLs..."
    $patch = "{`"data`":{`"STREAM_EXTERNAL_URL`":`"http://${STREAM_DNS}:5004`",`"UPLOAD_EXTERNAL_URL`":`"http://${UPLOAD_DNS}:5000`"}}"
    kubectl patch configmap service-config -n video-app --type merge -p $patch
    Write-Host "  Restarting frontend services to pick up new URLs..."
    kubectl rollout restart deployment/upload-service -n video-app
    kubectl rollout restart deployment/stream-service -n video-app
    kubectl rollout status deployment/upload-service -n video-app --timeout=60s
    kubectl rollout status deployment/stream-service -n video-app --timeout=60s
}
Write-Host ""

# Step 6: Deploy HPA
Write-Host "[6/6] Deploying Horizontal Pod Autoscalers..."
Write-Host "---------------------------------------------"
kubectl apply -f "$PROJECT_DIR\k8s\hpa.yaml"
Write-Host ""

# Summary
Write-Host "============================================="
Write-Host "  Deployment Complete!"
Write-Host "============================================="
Write-Host ""
Write-Host "Services:"
kubectl get svc -n video-app
Write-Host ""
Write-Host "Pods:"
kubectl get pods -n video-app
Write-Host ""
Write-Host "HPA Status:"
kubectl get hpa -n video-app
Write-Host ""
Write-Host "---------------------------------------------"
Write-Host "Access the application:"
if (-not [string]::IsNullOrEmpty($UPLOAD_DNS)) {
    Write-Host "  Upload Service: http://${UPLOAD_DNS}:5000"
} else {
    Write-Host "  Upload Service: kubectl port-forward svc/upload-service 5000:5000 -n video-app"
}
if (-not [string]::IsNullOrEmpty($STREAM_DNS)) {
    Write-Host "  Stream Service: http://${STREAM_DNS}:5004"
} else {
    Write-Host "  Stream Service: kubectl port-forward svc/stream-service 5004:5004 -n video-app"
}
Write-Host ""
Write-Host "Monitor HPA scaling:"
Write-Host "  kubectl get hpa -n video-app -w"
Write-Host ""
Write-Host "Run load test:"
Write-Host "  .\load-test.ps1"
Write-Host "============================================="
