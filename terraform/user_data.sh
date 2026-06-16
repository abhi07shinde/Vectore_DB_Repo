#!/bin/bash
# =============================================================================
# user_data.sh — EC2 Bootstrap Script
# Installs Docker and runs Qdrant vector database container
# Runs automatically on first EC2 boot via user_data
# =============================================================================

set -e
exec > /var/log/user_data.log 2>&1

echo "=========================================="
echo " Qdrant EC2 Bootstrap Starting..."
echo " Timestamp: $(date)"
echo "=========================================="

# ------------------------------------------------------------------------------
# 1. System Update
# ------------------------------------------------------------------------------
echo "[1/6] Updating system packages..."
apt-get update -y
apt-get upgrade -y

# ------------------------------------------------------------------------------
# 2. Install required dependencies
# ------------------------------------------------------------------------------
echo "[2/6] Installing dependencies..."
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  unzip \
  htop \
  awscli

# ------------------------------------------------------------------------------
# 3. Install Docker
# ------------------------------------------------------------------------------
echo "[3/6] Installing Docker..."

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable and start Docker
systemctl enable docker
systemctl start docker

echo "Docker version: $(docker --version)"

# ------------------------------------------------------------------------------
# 4. Mount EBS Volume for Qdrant persistent storage
# ------------------------------------------------------------------------------
echo "[4/6] Setting up EBS persistent storage..."

# Wait for the EBS volume to be attached (device: /dev/xvdf or /dev/nvme1n1)
DEVICE=""
for i in {1..12}; do
  if [ -b /dev/xvdf ]; then
    DEVICE="/dev/xvdf"
    break
  elif [ -b /dev/nvme1n1 ]; then
    DEVICE="/dev/nvme1n1"
    break
  fi
  echo "  Waiting for EBS volume... attempt $i/12"
  sleep 5
done

if [ -n "$DEVICE" ]; then
  # Format only if not already formatted
  if ! blkid "$DEVICE"; then
    echo "  Formatting $DEVICE as ext4..."
    mkfs.ext4 "$DEVICE"
  fi

  # Create mount point
  mkdir -p /qdrant-storage

  # Mount the volume
  mount "$DEVICE" /qdrant-storage

  # Add to fstab for persistence across reboots
  DEVICE_UUID=$(blkid -s UUID -o value "$DEVICE")
  if ! grep -q "$DEVICE_UUID" /etc/fstab; then
    echo "UUID=$DEVICE_UUID /qdrant-storage ext4 defaults,nofail 0 2" >> /etc/fstab
  fi

  echo "  EBS volume mounted at /qdrant-storage"
else
  echo "  WARNING: No EBS volume found, using instance storage (not recommended)"
  mkdir -p /qdrant-storage
fi

# Set correct permissions for Qdrant data directory
mkdir -p /qdrant-storage/data
chmod -R 755 /qdrant-storage

# ------------------------------------------------------------------------------
# 5. Pull and Run Qdrant Container
# ------------------------------------------------------------------------------
echo "[5/6] Pulling Qdrant Docker image..."
docker pull qdrant/qdrant:latest

echo "Starting Qdrant container..."
docker run -d \
  --name qdrant \
  --restart always \
  -p 6333:6333 \
  -p 6334:6334 \
  -v /qdrant-storage/data:/qdrant/storage \
  -e QDRANT__SERVICE__API_KEY="${qdrant_api_key}" \
  -e QDRANT__SERVICE__HOST="0.0.0.0" \
  -e QDRANT__LOG_LEVEL="INFO" \
  -e QDRANT__STORAGE__STORAGE_PATH="/qdrant/storage" \
  --memory="3.5g" \
  --cpus="1.8" \
  qdrant/qdrant:latest

echo "Qdrant container started."
docker ps

# ------------------------------------------------------------------------------
# 6. Install CloudWatch Agent
# ------------------------------------------------------------------------------
echo "[6/6] Installing CloudWatch Agent..."

wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb \
  -O /tmp/amazon-cloudwatch-agent.deb

dpkg -i /tmp/amazon-cloudwatch-agent.deb

# CloudWatch Agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCONFIG'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}"
    },
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/", "/qdrant-storage"],
        "metrics_collection_interval": 60
      },
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
        "totalcpu": true,
        "metrics_collection_interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/user_data.log",
            "log_group_name": "/qdrant/ec2/user-data",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
CWCONFIG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s

echo "=========================================="
echo " Bootstrap COMPLETE!"
echo " Qdrant is running on port 6333"
echo " API Key protection: ENABLED"
echo " Storage: /qdrant-storage"
echo " Timestamp: $(date)"
echo "=========================================="
