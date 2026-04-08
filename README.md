# Video Streaming Platform - AWS EKS Deployment Guide

## Architecture Overview

This project deploys a microservices-based video streaming platform on AWS EKS with Horizontal Pod Autoscaling (HPA).

### Services

| Service | Port | Description |
|---------|------|-------------|
| MySQL (StatefulSet) | 3306 | Database for users and video metadata |
| Auth Service | 5001 | User registration, login, JWT authentication |
| File Service | 5002 | Video file storage and streaming |
| MySQL API Service | 5003 | REST API wrapper for database operations |
| Upload Service | 5000 | Web UI for uploading videos |
| Stream Service | 5004 | Web UI for browsing and watching videos |

### Kubernetes Architecture Diagram

```
                    ┌──────────────────────────────────────────────┐
                    │              Kubernetes Cluster               │
                    │                                              │
  Users ──────────► │  ┌──────────────┐    ┌───────────────┐      │
        Port 5000   │  │Upload Service│    │Stream Service │ ◄──── Users
                    │  │ (2-10 pods)  │    │ (2-10 pods)   │      Port 5004
                    │  └──────┬───────┘    └───────┬───────┘      │
                    │         │                    │               │
                    │         ▼                    ▼               │
                    │  ┌─────────────┐  ┌──────────────┐          │
                    │  │Auth Service │  │ File Service  │          │
                    │  │ (2-10 pods) │  │ (2-10 pods)   │          │
                    │  └──────┬──────┘  └──────┬───────┘          │
                    │         │                │                   │
                    │         ▼                ▼                   │
                    │  ┌──────────────┐  ┌──────────┐             │
                    │  │MySQL API Svc │  │Video PVC │             │
                    │  │ (2-8 pods)   │  │ (10 Gi)  │             │
                    │  └──────┬───────┘  └──────────┘             │
                    │         │                                    │
                    │         ▼                                    │
                    │  ┌─────────────┐                             │
                    │  │   MySQL     │                             │
                    │  │(StatefulSet)│                             │
                    │  │  PVC (5Gi)  │                             │
                    │  └─────────────┘                             │
                    └──────────────────────────────────────────────┘
```

---

## Prerequisites

- **Docker** installed and running
- **kubectl** installed and configured
- **AWS CLI** installed and configured
- **eksctl** installed
- **An EKS cluster** running on AWS
- **Metrics Server** installed on the cluster (required for HPA)

---

## Step-by-Step Deployment

### Step 1: Set Up the EKS Cluster

```bash
eksctl create cluster \
  --name video-cluster \
  --region us-east-1 \
  --nodes 3 \
  --node-type t3.medium
```

### Step 2: Build and Push Docker Images

Navigate to the project root directory and build each service image:

```bash
cd infra2-main
```

Build, tag, and push images to your container registry:

```bash
docker build -t auth-service:latest ./auth_service
docker build -t file-service:latest ./file_service
docker build -t mysql-service:latest ./mysql_service
docker build -t upload-service:latest ./upload_service
docker build -t stream-service:latest ./stream_service
```

Tag and push to your registry (e.g., Docker Hub or ECR):

```bash
# Example for Docker Hub:
docker tag auth-service:latest YOUR_REGISTRY/auth-service:latest
docker push YOUR_REGISTRY/auth-service:latest
# Repeat for all services...
```

Then update the `image:` field in each YAML file to use the full registry path.

### Step 3: Deploy to Kubernetes

Use the deploy script to deploy everything at once. The script automatically:
1. Builds Docker images
2. Creates the namespace, secrets, and configmaps
3. Deploys MySQL, backend services, and frontend services
4. Waits for AWS to assign LoadBalancer DNS names
5. Patches the configmap with the real external URLs
6. Restarts frontend services to pick up the DNS
7. Deploys Horizontal Pod Autoscalers

```bash
chmod +x k8s/deploy.sh
./k8s/deploy.sh
```

Or deploy manually step by step:

```bash
# 1. Create namespace
kubectl apply -f k8s/namespace.yaml

# 2. Create secrets and config
kubectl apply -f k8s/secrets.yaml
kubectl apply -f k8s/configmap.yaml

# 3. Deploy MySQL database (must be ready before other services)
kubectl apply -f k8s/mysql-deployment.yaml
kubectl rollout status statefulset/mysql -n video-app --timeout=120s

# 4. Deploy backend services
kubectl apply -f k8s/auth-service.yaml
kubectl apply -f k8s/mysql-api-service.yaml
kubectl apply -f k8s/file-service.yaml

# Wait for backends to be ready
kubectl rollout status deployment/auth-service -n video-app --timeout=60s
kubectl rollout status deployment/mysql-service -n video-app --timeout=60s
kubectl rollout status deployment/file-service -n video-app --timeout=60s

# 5. Deploy frontend services
kubectl apply -f k8s/upload-service.yaml
kubectl apply -f k8s/stream-service.yaml

kubectl rollout status deployment/upload-service -n video-app --timeout=60s
kubectl rollout status deployment/stream-service -n video-app --timeout=60s

# 6. Deploy Horizontal Pod Autoscalers
kubectl apply -f k8s/hpa.yaml
```

### Step 4: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n video-app

# Check services
kubectl get svc -n video-app

# Check HPA
kubectl get hpa -n video-app
```

Expected output:

```
NAME              READY   STATUS    REPLICAS
mysql-0           1/1     Running   1
auth-service-xx   1/1     Running   2
file-service-xx   1/1     Running   2
mysql-service-xx  1/1     Running   2
upload-service-xx 1/1     Running   2
stream-service-xx 1/1     Running   2
```

### Step 5: Access the Application

Get the external AWS LoadBalancer DNS names:

```bash
kubectl get svc -n video-app
```

Use the `EXTERNAL-IP` (AWS ELB DNS) shown for `upload-service` and `stream-service`:

- Upload videos: `http://<upload-service-ELB-DNS>:5000`
- Watch videos: `http://<stream-service-ELB-DNS>:5004`

---

## Horizontal Pod Autoscaler (HPA) - Scalability Testing

### How HPA Works

The HPA monitors CPU utilization of each deployment. When average CPU usage exceeds **50%**, it automatically creates more pods (up to the maximum). When load decreases, it scales back down.

| Service | Min Pods | Max Pods | Scale-Up Trigger |
|---------|----------|----------|-----------------|
| Auth Service | 2 | 10 | CPU > 50% |
| File Service | 2 | 10 | CPU > 50% |
| MySQL API Service | 2 | 8 | CPU > 50% |
| Upload Service | 2 | 10 | CPU > 50% |
| Stream Service | 2 | 10 | CPU > 50% |

### Running the Load Test

#### Step 1: Check initial state

```bash
kubectl get hpa -n video-app
kubectl get pods -n video-app
```

You should see 2 pods per service (minimum replicas).

#### Step 2: Generate load

Option A - Use the provided load test script:

```bash
chmod +x k8s/load-test.sh
./k8s/load-test.sh
```

Option B - Deploy a load generator pod manually:

```bash
kubectl run load-generator -n video-app \
  --image=busybox \
  --restart=Never \
  -- /bin/sh -c "while true; do wget -q -O- http://auth-service:5001/health; wget -q -O- http://stream-service:5004/; wget -q -O- http://upload-service:5000/; done"
```

#### Step 3: Watch HPA scale up

Open a separate terminal and watch the HPA:

```bash
kubectl get hpa -n video-app -w
```

You will see `REPLICAS` increase as CPU utilization goes above 50%:

```
NAME                 REFERENCE              TARGETS    MINPODS  MAXPODS  REPLICAS
auth-service-hpa     Deployment/auth-svc    72%/50%    2        10       4
file-service-hpa     Deployment/file-svc    65%/50%    2        10       3
stream-service-hpa   Deployment/stream-svc  80%/50%    2        10       5
```

#### Step 4: Stop load and watch scale down

Stop the load test (Ctrl+C) or delete the load generator:

```bash
kubectl delete pod load-generator -n video-app
```

Then continue watching:

```bash
kubectl get hpa -n video-app -w
```

After the stabilization window (about 2 minutes), pods will gradually scale back down to the minimum (2 replicas).

---

## Useful Monitoring Commands

```bash
# Watch pods in real-time
kubectl get pods -n video-app -w

# Check resource usage (requires metrics-server)
kubectl top pods -n video-app

# View HPA details
kubectl describe hpa auth-service-hpa -n video-app

# View logs for a service
kubectl logs -l app=auth-service -n video-app --tail=50

# View events
kubectl get events -n video-app --sort-by='.lastTimestamp'
```

---

## Cleanup

Remove all resources:

```bash
kubectl delete namespace video-app
```

Or use the teardown script:

```bash
chmod +x k8s/teardown.sh
./k8s/teardown.sh
```

Delete the EKS cluster:

```bash
eksctl delete cluster --name video-cluster
```
