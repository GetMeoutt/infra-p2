# Video Streaming Platform - AWS EKS

## Project Overview
Microservices-based video streaming platform deployed on AWS EKS with HPA autoscaling.

## Services
| Service | Port | Image |
|---------|------|-------|
| MySQL (StatefulSet) | 3306 | mysql:8.0 |
| Auth Service | 5001 | tsripan/auth-service |
| File Service | 5002 | tsripan/file-service |
| MySQL API Service | 5003 | tsripan/mysql-service |
| Upload Service | 5000 | tsripan/upload-service |
| Stream Service | 5004 | tsripan/stream-service |

## Quick Deploy
To deploy the full stack on EKS, run:
```bash
# 1. Create EKS cluster (if not exists)
eksctl create cluster --name video-cluster1 --region us-east-1 --nodes 3 --node-type t3.medium

# 2. Install EBS CSI driver (required for PVCs on EKS)
eksctl utils associate-iam-oidc-provider --region us-east-1 --cluster video-cluster1 --approve
eksctl create addon --name aws-ebs-csi-driver --cluster video-cluster1 --region us-east-1 --force

# 3. Build, push, and deploy everything
docker build -t tsripan/auth-service:latest ./auth_service
docker build -t tsripan/file-service:latest ./file_service
docker build -t tsripan/mysql-service:latest ./mysql_service
docker build -t tsripan/upload-service:latest ./upload_service
docker build -t tsripan/stream-service:latest ./stream_service
docker push tsripan/auth-service:latest
docker push tsripan/file-service:latest
docker push tsripan/mysql-service:latest
docker push tsripan/upload-service:latest
docker push tsripan/stream-service:latest

# 4. Run deploy script (handles k8s manifests + auto-fetches ELB DNS)
sed -i 's/\r$//' k8s/deploy.sh
bash k8s/deploy.sh
# Or on PowerShell: .\k8s\deploy.ps1
```

## Teardown
```bash
kubectl delete namespace video-app
eksctl delete cluster --name video-cluster1 --region us-east-1
```

## Key Architecture Notes
- `MYSQL_HOST` uses fully qualified DNS: `mysql-0.mysql.video-app.svc.cluster.local`
- PVCs require `storageClassName: gp2` and the EBS CSI driver addon on EKS
- File-service runs 1 replica (EBS is ReadWriteOnce, can't share across nodes)
- Upload-service has 4Gi memory limit to handle large video uploads (up to 2GB)
- ELB idle timeout set to 600s via service annotation for large uploads
- Flask runs with `threaded=True` so health probes work during uploads
- Deploy script auto-fetches ELB DNS and patches the configmap
- Cross-service URLs (stream_url, upload_url) are set via env vars, not hardcoded
