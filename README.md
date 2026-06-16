# Qdrant Vector Database — AWS Infrastructure

> Terraform-managed EC2 deployment of Qdrant vector database on AWS (ap-south-1), deployed via GitHub Actions CI/CD pipeline.

---

## Architecture Overview

```
GitHub Actions (CI/CD)
        │
        ▼
   AWS ap-south-1
        │
   ┌────┴────────────────────────────────────┐
   │           Default VPC                   │
   │                                         │
   │   ┌─────────────────────────────────┐   │
   │   │  Security Group                 │   │
   │   │  ├─ Port 22  ← Admin IPs only   │   │
   │   │  ├─ Port 6333 ← Team access     │   │
   │   │  └─ Port 6334 ← Team access     │   │
   │   └────────────┬────────────────────┘   │
   │                │                        │
   │   ┌────────────▼────────────────────┐   │
   │   │  EC2 t3.medium                  │   │
   │   │  Ubuntu 22.04 LTS               │   │
   │   │  IAM Role (CW + SSM)            │   │
   │   │                                 │   │
   │   │  Docker Container               │   │
   │   │  └─ qdrant/qdrant:latest        │   │
   │   │     Port: 6333 (HTTP API)       │   │
   │   │     Port: 6334 (gRPC)           │   │
   │   │     API Key: ENABLED            │   │
   │   │     Restart: always             │   │
   │   └────────────┬────────────────────┘   │
   │                │                        │
   │   ┌────────────▼────────────────────┐   │
   │   │  EBS Volume (gp3, 40 GB)        │   │
   │   │  Mounted at /qdrant-storage     │   │
   │   │  Encrypted, Persistent          │   │
   │   └─────────────────────────────────┘   │
   │                                         │
   │   Elastic IP (stable, never changes)    │
   │   CloudWatch Monitoring + Alarms        │
   └─────────────────────────────────────────┘
```

---

## Project Structure

```
.
├── .github/
│   └── workflows/
│       └── terraform.yml       # GitHub Actions CI/CD pipeline
├── terraform/
│   ├── main.tf                 # EC2, SG, EBS, Elastic IP, IAM, CloudWatch
│   ├── variables.tf            # All configurable inputs
│   ├── outputs.tf              # Post-deploy outputs (IP, URL, etc.)
│   ├── backend.tf              # S3 remote state config
│   ├── provider.tf             # AWS provider and default tags
│   └── user_data.sh            # EC2 bootstrap (Docker + Qdrant)
└── README.md
```

---

## Prerequisites

### Step 1 — Create S3 Bucket for Terraform State

Run once manually before first deploy:

```bash
# Create bucket (use a unique name)
aws s3 mb s3://your-company-qdrant-tf-state --region ap-south-1

# Enable versioning (protects state history)
aws s3api put-bucket-versioning \
  --bucket your-company-qdrant-tf-state \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket your-company-qdrant-tf-state \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'
```

### Step 2 — Update backend.tf

Edit `terraform/backend.tf` and replace:
```hcl
bucket = "REPLACE_WITH_YOUR_BUCKET_NAME"
```
with your actual bucket name.

### Step 3 — Create EC2 Key Pair in AWS

```bash
# Option A: Create via CLI
aws ec2 create-key-pair \
  --key-name qdrant-key \
  --region ap-south-1 \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/qdrant-key.pem

chmod 400 ~/.ssh/qdrant-key.pem

# Option B: Create in AWS Console
# EC2 → Key Pairs → Create Key Pair → Download .pem
```

### Step 4 — Add GitHub Secrets

Go to your repo → **Settings → Secrets and Variables → Actions → New repository secret**

| Secret Name | Description | Example Value |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | IAM access key | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | IAM secret key | `wJalrXUtnFEMI/K7MDENG/...` |
| `AWS_REGION` | AWS region | `ap-south-1` |
| `TF_STATE_BUCKET` | S3 bucket for state | `your-company-qdrant-tf-state` |
| `SSH_KEY_NAME` | EC2 key pair name | `qdrant-key` |
| `QDRANT_API_KEY` | Qdrant API key | `eKMUATTm5JJtifdrrH3OTBCI1qPjVvzfF6fX9e90` |
| `ADMIN_SSH_CIDR` | Admin SSH IP CIDR | `103.x.x.x/32` |
| `TEAM_CIDR` | Team access CIDR | `0.0.0.0/0` or `203.x.x.x/24` |

> **QDRANT_API_KEY** generated for you: `eKMUATTm5JJtifdrrH3OTBCI1qPjVvzfF6fX9e90`
> Save this — you need it in all API calls.

---

## Deployment

### Automatic Deploy (Push to main)

```bash
git add .
git commit -m "feat: deploy qdrant infrastructure"
git push origin main
```

The pipeline runs automatically: `validate → plan → apply`

### Manual Trigger

Go to **Actions → Qdrant Infrastructure — Terraform → Run workflow**

Select action:
- `plan` — Preview changes only
- `apply` — Deploy infrastructure
- `destroy` — Tear down all resources (requires approval)

---

## Accessing Qdrant After Deploy

After `terraform apply` completes, outputs are printed in the GitHub Actions summary:

```
elastic_ip           = "x.x.x.x"
qdrant_endpoint      = "http://x.x.x.x:6333"
qdrant_dashboard_url = "http://x.x.x.x:6333/dashboard"
```

> **Wait 2–3 minutes** after first deploy for Docker and Qdrant to finish installing.

### Health Check

```bash
curl -H "api-key: eKMUATTm5JJtifdrrH3OTBCI1qPjVvzfF6fX9e90" \
  http://<ELASTIC_IP>:6333/healthz
```

Expected response: `{"title":"qdrant - vector search engine","version":"..."}`

### List Collections

```bash
curl -H "api-key: eKMUATTm5JJtifdrrH3OTBCI1qPjVvzfF6fX9e90" \
  http://<ELASTIC_IP>:6333/collections
```

### Open Dashboard in Browser

```
http://<ELASTIC_IP>:6333/dashboard
```

Enter your API key when prompted.

### Postman Setup

| Field | Value |
|---|---|
| Method | GET |
| URL | `http://<ELASTIC_IP>:6333/collections` |
| Header Key | `api-key` |
| Header Value | `eKMUATTm5JJtifdrrH3OTBCI1qPjVvzfF6fX9e90` |

### Python Client

```python
from qdrant_client import QdrantClient

client = QdrantClient(
    host="<ELASTIC_IP>",
    port=6333,
    api_key="eKMUATTm5JJtifdrrH3OTBCI1qPjVvzfF6fX9e90"
)

# Check connection
print(client.get_collections())
```

---

## SSH Access (Admin Only)

```bash
ssh -i ~/.ssh/qdrant-key.pem ubuntu@<ELASTIC_IP>

# Check Qdrant container status
sudo docker ps
sudo docker logs qdrant

# Check storage usage
df -h /qdrant-storage
```

---

## Scaling Guide

### Upgrade Instance Type (More RAM/CPU)

1. Edit `terraform/variables.tf`:
   ```hcl
   default = "t3.large"   # 8 GB RAM, 2 vCPU
   # or
   default = "t3.xlarge"  # 16 GB RAM, 4 vCPU
   ```
2. Push to main — pipeline handles the rest.

### Increase Storage

1. Edit `terraform/variables.tf`:
   ```hcl
   default = 100   # Increase to 100 GB
   ```
2. Push to main — EBS volume is resized without data loss.

### Restrict Team Access (When You Know Your Office IP)

1. Update GitHub Secret `TEAM_CIDR` to your office IP range (e.g. `203.x.x.x/24`)
2. Push any file change to trigger the pipeline — Security Group updates automatically.

---

## Cost Estimate (ap-south-1)

| Resource | Cost/Month (approx) |
|---|---|
| EC2 t3.medium | ~$15 |
| EBS gp3 40 GB | ~$3.20 |
| Elastic IP (attached) | Free |
| CloudWatch basic | Free tier |
| S3 state storage | ~$0.02 |
| **Total** | **~$18–20/month** |

---

## Troubleshooting

### Qdrant not responding after deploy

```bash
# SSH into instance and check bootstrap log
ssh -i ~/.ssh/qdrant-key.pem ubuntu@<IP>
cat /var/log/user_data.log

# Check Docker
sudo docker ps -a
sudo docker logs qdrant
```

### Port 6333 connection refused

- Check Security Group inbound rules in AWS Console
- Verify your IP matches the `TEAM_CIDR` secret
- Confirm Qdrant container is running: `sudo docker ps`

### Terraform state lock error

```bash
# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

### IP changed and SSH is blocked

Update GitHub Secret `ADMIN_SSH_CIDR` with your new IP and push to trigger a pipeline run.
