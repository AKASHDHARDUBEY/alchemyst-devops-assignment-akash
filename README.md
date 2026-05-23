# DevOps Internship Assignment

This repository contains the infrastructure and deployment automation for the `quickstart` distributed inferencing prototype on AWS.

## Architecture Diagram

```ascii
                      +-------------------+
                      |   Public Internet |
                      +---------+---------+
                                | HTTP (Port 3111)
                                v
+-------------------------------------------------------------+
| VPC (10.0.0.0/16)                                           |
|                                                             |
|   +-----------------------------------------------------+   |
|   | Public Subnet (10.0.1.0/24)                         |   |
|   |                                                     |   |
|   |  +--------------------+       +------------------+  |   |
|   |  | API Gateway VM     |       |   NAT Gateway    |  |   |
|   |  | (iii engine)       |       |   (EIP)          |  |   |
|   |  | Port 3111 (HTTP)   |       +---------+--------+  |   |
|   |  | Port 49134 (WS)    |                 |           |   |
|   |  +---------+----------+                 |           |   |
|   +------------|----------------------------|-----------+   |
|                |                            |               |
|                | WebSocket (RPC)            | Internet      |
|                |                            | Access        |
|   +------------|----------------------------|-----------+   |
|   | Private Subnet (10.0.2.0/24)            |           |   |
|   |                                         v           |   |
|   |  +--------------------+       +------------------+  |   |
|   |  | TS Caller Worker   |       | Python Inference |  |   |
|   |  | (caller-worker)    |       | (math-worker)    |  |   |
|   |  | connects to WS     |       | connects to WS   |  |   |
|   |  +--------------------+       +------------------+  |   |
|   +-----------------------------------------------------+   |
+-------------------------------------------------------------+
```

## How to Redeploy from Scratch

### 1. Prerequisites
- [Terraform](https://www.terraform.io/downloads.html) installed.
- AWS CLI configured with administrator credentials.
- An existing EC2 Key Pair named `devops-assignment-key` in `us-east-1` (or change the default in `terraform/variables.tf`).

### 2. Provision Infrastructure
Run the following commands to provision the network and virtual machines:

```bash
cd terraform
terraform init
terraform apply -auto-approve
```

After successful application, Terraform will output the public and private IP addresses for the instances:
- `api_gateway_public_ip`
- `api_gateway_private_ip`
- `ts_worker_private_ip`
- `python_worker_private_ip`

### 3. Deploy Application and Workers
Use the provided bash script to copy the code to the VMs and setup `systemd` services for each component. The deployment script uses SSH ProxyJump through the API Gateway to securely configure the workers inside the private subnet.

To run the deployment script, execute from the root directory:

```bash
./deployment/deploy.sh ~/.ssh/devops-assignment-key.pem <API_GW_PUBLIC_IP> <TS_WORKER_PRIVATE_IP> <PYTHON_WORKER_PRIVATE_IP> <API_GW_PRIVATE_IP>
```

### 4. Test the API
Once all services are running, the HTTP endpoint will be available via the API Gateway's public IP.

**Sample Curl Command:**
```bash
curl -X POST http://<API_GW_PUBLIC_IP>:3111/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {
        "role": "user",
        "content": "Explain quantum entanglement in simple terms."
      }
    ]
  }'
```

**Sample Response:**
```json
{
  "result": {
    "result": "Quantum entanglement is a phenomenon where two or more particles become connected in such a way that their properties are correlated...",
    "success": "You've connected two workers and they're interoperating seamlessly, now let's add a few more workers to expand this project's functionality."
  }
}
```

## Production Hardening & Scaling Thoughts

**What to harden before putting this in production:**
1. **Security & Access Control**: The `iii` API Gateway HTTP endpoint and WebSocket interfaces are currently completely open. In production, an AWS Application Load Balancer (ALB) or API Gateway (managed) should be placed in front of it to handle TLS termination (HTTPS) and rate limiting. 
2. **Authentication**: The HTTP endpoints and worker connections need proper authentication/authorization tokens (JWT, API keys) instead of allowing open network access, even if confined to a VPC.
3. **Infrastructure Refinement**: Instead of manual SSH scripts, deployment should be fully automated utilizing immutable AMIs (Packer), Auto Scaling Groups (ASGs), or containerized with EKS/ECS (Fargate).
4. **Monitoring & Observability**: Although `iii-observability` is enabled in config, metrics and logs should be shipped to centralized logging systems like CloudWatch, Datadog, or Prometheus/Grafana rather than storing in memory.

**What to do differently if the model were 100x larger:**
1. **Hardware Selection**: A 100x larger model (e.g., 30B to 70B parameter models) would mandate GPUs. We'd switch from CPU-bound `t3`/`t4g` instances to GPU-optimized instances like `g5`, `p4`, or `p5` families (NVIDIA A10G, A100, or H100).
2. **Inference Optimization**: `transformers` is often insufficient for serving massive models efficiently at scale. I would deploy a dedicated inference server like vLLM, Text Generation Inference (TGI), or TensorRT-LLM which provides Continuous Batching and PagedAttention to dramatically boost throughput and reduce memory fragmentation.
3. **Model Sharding**: If the model exceeds the VRAM of a single GPU, tensor parallelism across multiple GPUs or even multiple nodes would be necessary.
4. **Decoupled Asynchronous Processing**: Large models have high latency. I would introduce an asynchronous queueing system (like SQS, Kafka, or RabbitMQ) rather than keeping HTTP connections hanging, possibly leveraging webhooks or SSE for the final response delivery.
