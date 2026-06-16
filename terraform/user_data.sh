#!/bin/bash
set -euxo pipefail
exec > /var/log/user_data.log 2>&1

apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release

# Install Docker
install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
| tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io

systemctl start docker
systemctl enable docker

# Wait for EBS
for i in {1..12}; do
  DEVICE=$(lsblk -dpno NAME | grep -E "nvme1n1|xvdf" | head -n 1 || true)
  if [ -n "$DEVICE" ]; then break; fi
  sleep 5
done

mkdir -p /qdrant-storage

if [ -n "$DEVICE" ]; then
  if ! blkid "$DEVICE"; then
    mkfs.ext4 "$DEVICE"
  fi

  mount "$DEVICE" /qdrant-storage
fi

mkdir -p /qdrant-storage/data

docker rm -f qdrant || true

docker run -d \
  --name qdrant \
  -p 6333:6333 \
  -v /qdrant-storage/data:/qdrant/storage \
  -e QDRANT__SERVICE__API_KEY="${qdrant_api_key}" \
  qdrant/qdrant:latest

docker ps

# ------------------------------------------------------------------------------
# 6. CloudWatch Agent
# ------------------------------------------------------------------------------
echo "[6/6] Installing CloudWatch..."

wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb \
  -O /tmp/cwagent.deb

dpkg -i /tmp/cwagent.deb

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
  "agent": { "metrics_collection_interval": 60 },
  "metrics": {
    "append_dimensions": { "InstanceId": "${aws:InstanceId}" },
    "metrics_collected": {
      "mem": { "measurement": ["mem_used_percent"] },
      "disk": { "measurement": ["used_percent"], "resources": ["/", "/qdrant-storage"] },
      "cpu": { "measurement": ["cpu_usage_idle"], "totalcpu": true }
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
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

# ------------------------------------------------------------------------------
# DONE
# ------------------------------------------------------------------------------
echo "=========================================="
echo "Bootstrap COMPLETE"
echo "Qdrant running on: http://<EC2-IP>:6333"
echo "=========================================="