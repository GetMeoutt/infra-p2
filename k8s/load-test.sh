#!/bin/bash
# =============================================================================
# Load Test Script for Horizontal Pod Autoscaler (HPA) Demonstration
# =============================================================================
# This script generates high CPU load on the backend services to trigger
# the HPA to scale up. After stopping, HPA will scale back down.
#
# Prerequisites:
#   - kubectl configured and connected to your cluster
#   - Application deployed in the video-app namespace
#   - Metrics Server installed and running
#
# Usage:
#   chmod +x load-test.sh
#   ./load-test.sh
# =============================================================================

NAMESPACE="video-app"

echo "============================================="
echo "  HPA Load Test - Video Streaming Platform"
echo "============================================="
echo ""

# Step 1: Show current state before load test
echo "[1/4] Current HPA status (BEFORE load test):"
echo "---------------------------------------------"
kubectl get hpa -n $NAMESPACE
echo ""
echo "Current pod count:"
kubectl get pods -n $NAMESPACE -o wide | grep -E "NAME|Running"
echo ""

# Step 2: Get service endpoints
UPLOAD_SVC=$(kubectl get svc upload-service -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
STREAM_SVC=$(kubectl get svc stream-service -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

# Fallback to NodePort if LoadBalancer IP not available
if [ -z "$UPLOAD_SVC" ]; then
    echo "LoadBalancer IP not available. Using port-forward instead."
    echo "Starting port-forwards in background..."
    kubectl port-forward svc/upload-service 5000:5000 -n $NAMESPACE &
    PF_UPLOAD_PID=$!
    kubectl port-forward svc/stream-service 5004:5004 -n $NAMESPACE &
    PF_STREAM_PID=$!
    kubectl port-forward svc/auth-service 5001:5001 -n $NAMESPACE &
    PF_AUTH_PID=$!
    sleep 3
    UPLOAD_URL="http://localhost:5000"
    STREAM_URL="http://localhost:5004"
    AUTH_URL="http://localhost:5001"
else
    UPLOAD_URL="http://$UPLOAD_SVC:5000"
    STREAM_URL="http://$STREAM_SVC:5004"
    AUTH_URL="http://$UPLOAD_SVC:5001"
fi

echo ""
echo "[2/4] Generating load on backend services..."
echo "---------------------------------------------"
echo "Sending concurrent requests to simulate high traffic."
echo "Press Ctrl+C to stop the load test."
echo ""

# Function to generate load
generate_load() {
    local url=$1
    local name=$2
    echo "  Starting load on $name ($url)..."
    while true; do
        # Send 20 concurrent requests
        for i in $(seq 1 20); do
            curl -s -o /dev/null "$url" &
        done
        wait
    done
}

# Also run a CPU-intensive load generator pod inside the cluster
echo "  Deploying in-cluster load generator..."
kubectl run load-generator \
    --image=busybox \
    --namespace=$NAMESPACE \
    --restart=Never \
    --command -- /bin/sh -c "
    while true; do
        wget -q -O- http://auth-service:5001/health > /dev/null 2>&1 &
        wget -q -O- http://file-service:5002/health > /dev/null 2>&1 &
        wget -q -O- http://mysql-service:5003/health > /dev/null 2>&1 &
        wget -q -O- http://upload-service:5000/ > /dev/null 2>&1 &
        wget -q -O- http://stream-service:5004/ > /dev/null 2>&1 &
    done
" 2>/dev/null

# Start load generation in background
generate_load "$AUTH_URL/health" "Auth Service" &
LOAD_PID_1=$!
generate_load "$UPLOAD_URL" "Upload Service" &
LOAD_PID_2=$!
generate_load "$STREAM_URL" "Stream Service" &
LOAD_PID_3=$!

# Cleanup function
cleanup() {
    echo ""
    echo ""
    echo "[3/4] Stopping load test..."
    echo "---------------------------------------------"
    kill $LOAD_PID_1 $LOAD_PID_2 $LOAD_PID_3 2>/dev/null
    kill $PF_UPLOAD_PID $PF_STREAM_PID $PF_AUTH_PID 2>/dev/null
    kubectl delete pod load-generator -n $NAMESPACE 2>/dev/null
    wait 2>/dev/null
    echo "Load generation stopped."
    echo ""
    echo "[4/4] HPA status (AFTER load test):"
    echo "---------------------------------------------"
    kubectl get hpa -n $NAMESPACE
    echo ""
    echo "Current pod count:"
    kubectl get pods -n $NAMESPACE
    echo ""
    echo "============================================="
    echo "  Watch HPA scale down over the next few"
    echo "  minutes with:"
    echo "  kubectl get hpa -n video-app -w"
    echo "============================================="
    exit 0
}

trap cleanup SIGINT SIGTERM

# Monitor HPA while load is being generated
echo ""
echo "[MONITORING] Watching HPA scaling (updates every 15s)..."
echo "Press Ctrl+C to stop."
echo ""
while true; do
    echo "--- $(date) ---"
    kubectl get hpa -n $NAMESPACE
    echo ""
    kubectl get pods -n $NAMESPACE --no-headers | wc -l | xargs -I{} echo "Total pods: {}"
    echo ""
    sleep 15
done
