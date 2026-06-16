
set -euxo pipefail
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

install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
| tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y

apt-get install -y \
  docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker

# Allow ubuntu user to run docker
usermod -aG docker ubuntu

echo "Docker installed: $(docker --version)"

# ------------------------------------------------------------------------------
# 4. Mount EBS Volume for Qdrant
# ------------------------------------------------------------------------------
echo "[4/6] Setting up EBS storage..."

DEVICE=""

for i in {1..12}; do
  DEVICE=$(lsblk -dpno NAME | grep -E "nvme1n1|xvdf" | head -n 1 || true)
  if [ -n "$DEVICE" ]; then
    break
  fi
  echo "Waiting for EBS volume... attempt $i/12"
  sleep 5
done

if [ -n "$DEVICE" ]; then
  if ! blkid "$DEVICE"; then
    echo "Formatting $DEVICE as ext4..."
    mkfs.ext4 "$DEVICE"
  fi

  mkdir -p /qdrant-storage
  mount "$DEVICE" /qdrant-storage

  DEVICE_UUID=$(blkid -s UUID -o value "$DEVICE")

  if ! grep -q "$DEVICE_UUID" /etc/fstab; then
    echo "UUID=$DEVICE_UUID /qdrant-storage ext4 defaults,nofail 0 2" >> /etc/fstab
  fi

  echo "Mounted EBS at /qdrant-storage"
else
  echo "WARNING: No EBS found. Using local storage."
  mkdir -p /qdrant-storage
fi

mkdir -p /qdrant-storage/data
chmod -R 755 /qdrant-storage

# ------------------------------------------------------------------------------
# 5. Run Qdrant Container
# ------------------------------------------------------------------------------
echo "[5/6] Starting Qdrant..."

docker rm -f qdrant || true

docker pull qdrant/qdrant:latest

docker run -d \
  --name qdrant \
  --restart always \
  -p 6333:6333 \
  -p 6334:6334 \
  -v /qdrant-storage/data:/qdrant/storage \
  -e QDRANT__SERVICE__API_KEY="my-secret-api-key" \
  -e QDRANT__SERVICE__HOST="0.0.0.0" \
  -e QDRANT__LOG_LEVEL="INFO" \
  -e QDRANT__STORAGE__STORAGE_PATH="/qdrant/storage" \
  qdrant/qdrant:latest

echo "Qdrant container running:"
docker ps

# ------------------------------------------------------------------------------
# 6. Install CloudWatch Agent
# ------------------------------------------------------------------------------
echo "[6/6] Installing CloudWatch Agent..."

wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb \
  -O /tmp/amazon-cloudwatch-agent.deb

dpkg -i /tmp/amazon-cloudwatch-agent.deb

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
        "measurement": ["mem_used_percent"]
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/", "/qdrant-storage"]
      },
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
        "totalcpu": true
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

# ------------------------------------------------------------------------------
# DONE
# ------------------------------------------------------------------------------
echo "=========================================="
echo " BOOTSTRAP COMPLETE!"
echo " Qdrant running on port 6333"
echo " API Key: ENABLED"
echo " Storage: /qdrant-storage"
echo " Timestamp: $(date)"
echo "=========================================="
