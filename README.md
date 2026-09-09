# ARCHITECTURAL SPECIFICATION & IMPLEMENTATION GUIDE

**Pattern:** API Façade in Agentic Account via AWS PrivateLink

**Target Accounts:** `agent-ai` (Agentic Workload Account) | `vrm-sandbox` (Application / EKS Account)

---

## Executive Summary

To achieve the maximum security posture, direct cross-account IAM permissions for Amazon Bedrock and AgentCore are eliminated from the Application account (`vrm-sandbox`). Instead, an API Façade (a lightweight proxy service) is deployed in the Agentic account (`agent-ai`) behind an internal Network Load Balancer (NLB) and exposed via an AWS PrivateLink Endpoint Service.

### Key Security Outcomes

* **Zero Bedrock Credentials:** The `vrm-sandbox` account and its EKS workloads hold no direct `bedrock:*` permissions.


* **Centralized Governance:** Model allow-lists, token budget enforcement, guardrails, and audit logging are strictly managed by the Façade in `agent-ai`.


* **Network Isolation:** Traffic flows purely over the AWS private network backbone via PrivateLink interface endpoints—no public internet, no route table sharing, and no broad VPC peering.



---

## Architecture Diagram

```
+----------------------------------------------------------------------------------------------------------------+
|                                           AWS ACCOUNT: vrm-sandbox                                             |
|                                                                                                                |
|  +----------------------------------------------------------------------------------------------------------+  |
|  | VPC (App / EKS VPC)                                                                                      |  |
|  |                                                                                                          |  |
|  |   +--------------------------+                         +---------------------------------------------+   |  |
|  |   | EKS Cluster              |                         | Interface VPC Endpoint                      |   |  |
|  |   |  (Pods / Microservices)  |                         | (vpce-xxxxxx)                               |   |  |
|  |   |                          |                         |  - Private IP in Subnets                    |   |  |
|  |   | Calls Façade API over    |========================>|  - Private DNS: agent-ai.internal.local    |   |  |
|  |   | local private IP/DNS     |  (Strictly Private)     +----------------------+----------------------+   |  |
|  |   +--------------------------+                                                |                         |  |
|  +-------------------------------------------------------------------------------|--------------------------+  |
+----------------------------------------------------------------------------------|-----------------------------+
                                                                                   |
                                                 AWS PrivateLink Connection        | (No Public Internet)
                                                 (Unidirectional Security Boundary)|
                                                                                   v
+----------------------------------------------------------------------------------------------------------------+
|                                           AWS ACCOUNT: agent-ai                                                |
|                                                                                                                |
|  +----------------------------------------------------------------------------------------------------------+  |
|  | VPC (Agentic / Infra VPC)                                                                                |  |
|  |                                                                                                          |  |
|  |   +--------------------------+       +-------------------+       +-----------------------------------+   |  |
|  |   | VPC Endpoint Service     |<======| Network Load      |<======| Invocation Service Façade         |   |  |
|  |   | (com.amazonaws.vpce...)  |       | Balancer (NLB)    |       | (ECS Fargate / Private API GW)    |   |  |
|  |   +--------------------------+       +-------------------+       +-----------------+-----------------+   |  |
|  |                                                                                    |                     |  |
|  |                                                                                    | Attaches Agent      |  |
|  |                                                                                    | Execution Role      |  |
|  |                                                                                    v                     |  |
|  |                                                                  +-----------------------------------+   |  |
|  |                                                                  | AWS Bedrock / AgentCore           |   |  |
|  |                                                                  | - Guardrails & Token Controls     |   |  |
|  |                                                                  | - Agent Execution Runtime         |   |  |
|  |                                                                  +-----------------------------------+   |  |
|  +----------------------------------------------------------------------------------------------------------+  |
+----------------------------------------------------------------------------------------------------------------+

```

---

## Phase 1: Implementation Steps in `agent-ai` Account

### 1. Deploy the Façade Service

Deploy an internal proxy microservice using ECS Fargate, Lambda behind a VPC, or a Private REST API Gateway.

**Required IAM Task Role Policy for the Façade (`agent-ai`):**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BedrockAgentCoreAccess",
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
        "bedrock-agent-runtime:InvokeAgent"
      ],
      "Resource": "*"
    }
  ]
}

```

### 2. Configure Internal Network Load Balancer (NLB)

1. Navigate to **VPC Console** $\rightarrow$ **Target Groups** $\rightarrow$ Create a target group pointing to the Façade tasks/IPs on TCP port `443` or `80`.
2. Create an **Internal Network Load Balancer (NLB)** in your private subnets.


3. Add a listener forwarding traffic to the target group created above.

### 3. Provision VPC Endpoint Service (PrivateLink Provider)

1. Go to **VPC Console** $\rightarrow$ **Endpoint Services** $\rightarrow$ **Create Endpoint Service**.
2. Select the Internal NLB created in step 2.


3. Enable **Acceptance required**.


4. Under **Allowed Principals**, explicitly authorize the `vrm-sandbox` account:
`arn:aws:iam::<VRM_SANDBOX_ACCOUNT_ID>:root`
5. Copy the generated **Service Name** (e.g., `com.amazonaws.vpce.us-east-1.vpce-svc-xxxxxxxxxxxxxxxxx`).



---

## Phase 2: Implementation Steps in `vrm-sandbox` Account

### 1. Apply Bedrock Explicit Deny Safeguard

To guarantee zero drift or misuse, apply an IAM boundary or policy statement to all EKS execution/pod roles to explicitly block direct Bedrock access:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BlockDirectBedrockAccess",
      "Effect": "Deny",
      "Action": [
        "bedrock:*"
      ],
      "Resource": "*"
    }
  ]
}

```

### 2. Create Interface VPC Endpoint (Consumer)

1. Navigate to **VPC Console** $\rightarrow$ **Endpoints** $\rightarrow$ **Create Endpoint**.
2. Select **Other endpoint services**.
3. Service Name: Paste the `com.amazonaws.vpce...` string from the `agent-ai` account. Click **Verify service**.


4. Select your **EKS VPC** and private subnets.


5. Security Group: Create/assign a Security Group that permits inbound port `443` traffic from your EKS worker node security group.

### 3. Accept Endpoint Connection in `agent-ai` Account

1. Switch back to the `agent-ai` AWS Console.
2. Go to **VPC Console** $\rightarrow$ **Endpoint Services** $\rightarrow$ Select your endpoint service.


3. Under **Endpoint connections**, select the pending request from `vrm-sandbox` and click **Accept endpoint connection request**.



---

## Phase 3: Application Code Integration

EKS microservices do not need the standard AWS Bedrock SDK (`boto3`). Instead, pods make standard HTTP/REST requests to the local VPC Endpoint DNS/IP provisioned in Phase 2.

### Python Code Snippet (EKS App Pod)

```python
import requests

# Private Endpoint DNS created by PrivateLink in vrm-sandbox
FACADE_ENDPOINT_URL = "https://vpce-xxxxxx.agent-ai.internal.local/v1/agent/invoke"

def invoke_agent_facade(prompt: str, session_id: str):
    payload = {
        "prompt": prompt,
        "session_id": session_id,
        "client_app": "vrm-sandbox-eks"
    }
    
    headers = {
        "Content-Type": "application/json"
    }
    
    # Strictly private network call - no AWS credentials required in vrm-sandbox
    response = requests.post(
        FACADE_ENDPOINT_URL, 
        json=payload, 
        headers=headers, 
        timeout=30
    )
    
    if response.status_code == 200:
        return response.json()
    else:
        raise Exception(f"Invocation failed: {response.status_code} - {response.text}")

```

---

## Verification & Auditing Checklist

* [ ] **Credential Audit:** Confirm no Pod in `vrm-sandbox` possesses AWS credentials with `bedrock:*` or `bedrock-agent-runtime:*` permissions.


* [ ] **Network Isolation:** Confirm the VPC Endpoint SG in `vrm-sandbox` only accepts traffic originating from EKS worker node security groups.
* [ ] **Logging Centralization:** Ensure the Façade in `agent-ai` streams all prompt/response metadata, token usage, and caller identities to Amazon CloudWatch / S3 in a centralized log account.