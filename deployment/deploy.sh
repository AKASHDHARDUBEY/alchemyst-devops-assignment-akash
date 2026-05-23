#!/bin/bash

# Deployment script for DevOps Internship Assignment

set -e

KEY_PATH=$1
API_GW_IP=$2
TS_WORKER_IP=$3
PYTHON_WORKER_IP=$4
API_GW_PRIVATE_IP=$5

if [ -z "$5" ]; then
  echo "Usage: ./deploy.sh <path_to_ssh_key> <api_gateway_ip> <ts_worker_ip> <python_worker_ip> <api_gateway_private_ip>"
  exit 1
fi

echo "=============================================="
echo " Deploying API Gateway & Engine "
echo "=============================================="

# Copy engine config
scp deployment/engine-config.yaml ubuntu@$API_GW_IP:~/config.yaml

# Setup API Gateway
ssh ubuntu@$API_GW_IP << 'EOF'
  curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
  sudo mv ~/.local/bin/iii /usr/local/bin/
  
  cat << 'UNIT' | sudo tee /etc/systemd/system/iii-engine.service
[Unit]
Description=iii Engine
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu
ExecStart=/usr/local/bin/iii --config config.yaml
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

  sudo systemctl daemon-reload
  sudo systemctl enable --now iii-engine
EOF

echo "API Gateway Private IP is $API_GW_PRIVATE_IP"

echo "=============================================="
echo " Deploying Caller Worker (TypeScript) "
echo "=============================================="

scp -r quickstart ubuntu@$TS_WORKER_IP:~/quickstart

ssh ubuntu@$TS_WORKER_IP << EOF
  # Setup Swap
  if [ ! -f /swapfile ]; then
    sudo fallocate -l 2G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  fi

  curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
  sudo mv ~/.local/bin/iii /usr/local/bin/
  
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs
  
  cd ~/quickstart/workers/caller-worker
  npm install
  
  cat << 'UNIT' | sudo tee /etc/systemd/system/iii-caller.service
[Unit]
Description=iii Caller Worker
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/quickstart/workers/caller-worker
Environment="III_URL=ws://$API_GW_PRIVATE_IP:49134"
ExecStart=/usr/bin/npm run dev
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

  sudo systemctl daemon-reload
  sudo systemctl enable --now iii-caller
EOF

echo "=============================================="
echo " Deploying Inference Worker (Python) "
echo "=============================================="

scp -r quickstart ubuntu@$PYTHON_WORKER_IP:~/quickstart

ssh ubuntu@$PYTHON_WORKER_IP << EOF
  # Setup Swap
  if [ ! -f /swapfile ]; then
    sudo fallocate -l 2G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  fi

  sudo apt-get update
  sudo apt-get install -y python3 python3-pip python3-venv

  cd ~/quickstart/workers/inference-worker
  rm -rf venv
  python3 -m venv venv
  source venv/bin/activate
  pip install torch --index-url https://download.pytorch.org/whl/cpu
  pip install -r requirements.txt
  
  cat << 'UNIT' | sudo tee /etc/systemd/system/iii-inference.service
[Unit]
Description=iii Inference Worker
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/quickstart/workers/inference-worker
Environment="III_URL=ws://$API_GW_PRIVATE_IP:49134"
ExecStart=/home/ubuntu/quickstart/workers/inference-worker/venv/bin/python inference_worker.py
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

  sudo systemctl daemon-reload
  sudo systemctl enable --now iii-inference
EOF

echo "=============================================="
echo " Deployment Complete! "
echo " API Gateway exposed at http://$API_GW_IP:3111 "
echo "=============================================="
