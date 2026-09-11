
# ARCHITECTURE REVIEW & COMPARATIVE ASSESSMENT: AAIS-001 v0.2

**Target Accounts:** `vrm-sandbox` (App / EKS Account) | `vrm-ai` (Dedicated Agent Account / OU `ou-2qlc-c7r7zow1`)

---

## 1. Executive Summary & Verdict

The target architecture proposes a **zero-trust, data-isolated AI execution sandbox** within a dedicated AWS account (`vrm-ai`). The design establishes a strict boundary where **customer data never rests inside the AI account**, compute is ephemeral per session, and outbound egress from the AI account is denied by default.

### Core Principles Established

* **Zero Customer Data at Rest:** Compute is ephemeral (per-session microVMs using `MMDSv2`). No databases, S3 credential grants, or persistent storage layers exist inside `vrm-ai`.


* **Strict Deny-by-Default Egress:** The Agent VPC contains private subnets only—**no Internet Gateway (IGW), no NAT Gateway, and no VPC Peering**.


* **Controlled Inbound Trigger Path:** Invocations travel from EKS Sidekiq workers via an AWS PrivateLink Interface Endpoint (`com.amazonaws.us-east-1.bedrock-agentcore`). Inbound access is governed by dual resource-based policies enforcing both the Sidekiq IRSA role and the specific Endpoint ID.


* **Controlled Return Path via AWS VPC Lattice:** Tool calls from the agent back to the Rails application travel over **AWS VPC Lattice** (shared cross-account via AWS RAM) targeting an internal ALB.


* **Cedar Policy Engine:** Tool calls are intercepted and evaluated parameter-by-parameter using Cedar rules in the **AgentCore Gateway**.



---

## 2. Architecture Comparison: Existing Façade Model vs. Target `AAIS-001 v0.2`

| Architectural Aspect | Initial Façade Proposal (NLB + ECS Proxy)

 | Lead's Proposed Target (`AAIS-001 v0.2`)

 |
| --- | --- | --- |
| **Inbound Path (App $\rightarrow$ AI)** | PrivateLink $\rightarrow$ NLB $\rightarrow$ ECS Façade App

 | Direct PrivateLink to native `com.amazonaws.us-east-1.bedrock-agentcore`<br> |
| **Return Path (AI $\rightarrow$ App Tools)** | PrivateLink or API Gateway

 | **AWS VPC Lattice Resource Gateway** (Shared via AWS RAM)

 |
| **Tool Authorization** | Custom application logic inside proxy

 | **AgentCore Gateway Policy Engine (Cedar Rules)**<br> |
| **State Management** | External DB or AgentCore Memory

 | **Zero Durable State** (AgentCore Memory explicitly rejected)

 |
| **Tenant Isolation** | Evaluated at Façade application layer

 | **Run Token Scope:** Rails controls every read/write; model IDs are untrusted

 |
| **Network Egress Guardrails** | Standard Security Groups

 | Deny-by-default egress, strict SCPs blocking IGW/NAT/peering

 |

---

## 3. End-to-End Execution Flow

```
[ vrm-sandbox / App Account ]                                      [ vrm-ai / Agent Account ]
+---------------------------------+                               +----------------------------------+
| Amazon EKS (Rails / Sidekiq)    |                               | AWS Bedrock AgentCore            |
|                                 |                               | - Ephemeral microVMs (MMDSv2)    |
| 1. InvokeAgentRuntime           |                               | - Deny-by-default egress         |
|    (with run token & docs)      |                               |                                  |
|   +-------------------------+   |   PrivateLink Endpoint        |   +--------------------------+   |
|   | Sidekiq Worker IRSA     |===|==============================>|   | AgentCore Runtime        |   |
|   +-------------------------+   |  (Inbound Only + Condition)   |   +------------+-------------+   |
|                                 |                               |                |               |
|                                 |                               | 2. Converse    | (Bedrock)     |
|                                 |                               |                v               |
|                                 |                               |   +--------------------------+   |
|                                 |                               |   | Bedrock Runtime Endpoint |   |
|                                 |                               |   +--------------------------+   |
|                                 |                               |                |               |
| 4. Tool Calls (MCP / HTTPS)     |   AWS VPC Lattice             | 3. Tool Calls  | (Cedar Rules) |
|    (Reads & Writes)             |   (RAM-Shared Resource)       |                v               |
|   +-------------------------+   |<==============================|===+--------------------------+   |
|   | Internal ALB            |   |                               |   | AgentCore Gateway        |   |
|   +------------+------------+   |                               |   +--------------------------+   |
|                |                |                               +----------------------------------+
|                v                |
|   +-------------------------+   |
|   | Rails App (Scope Engine)|   |
|   +------------+------------+   |
|                |                |
|                v                |
|   +-------------------------+   |
|   | Amazon RDS / S3         |   |
|   +-------------------------+   |
+---------------------------------+

```

### Detailed Flow Steps



1. **Invocation:** The Sidekiq worker invokes `InvokeAgentRuntime` over PrivateLink passing the prompt payload, inline documents, and a short-lived run-scoped job token.


2. **Inference:** The runtime calls `Converse` through the `bedrock-runtime` interface endpoint using cross-region inference profiles.


3. **Tool Execution:** Tool calls emitted by the model are intercepted by the **AgentCore Gateway Policy Engine**. Cedar rules validate parameter-level budgets and session conditions before releasing requests.


4. **VPC Lattice Egress:** Authorized tool requests travel across **VPC Lattice** to the internal ALB (`internal-agent-tools.internal.smarshvrm.com`) in `vrm-sandbox`.


5. **State & Read/Write Enforcement:** Rails executes API actions against RDS and S3. Authorization scope is derived strictly from the **run token**, preventing model parameter tampering.



---

## 4. Explicitly Rejected Features & Safety Rationale

* **Browser Tool:** Excluded because it requires public internet egress via NAT Gateway, breaking the zero-egress posture.


* **Code Interpreter:** Excluded to eliminate arbitrary code execution risks inside the execution sandbox.


* **AgentCore Memory:** Excluded to ensure customer data is never persisted at rest inside the AI account.



---

## 5. Technical Specifications for Implementation

### Dual Inbound Resource Policy Specification (`vrm-ai`)

Inbound PrivateLink execution requires matching `Allow` statements on **both** the AgentCore Runtime and its Endpoint resource policies:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowSidekiqIRSAOnly",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::<APP_ACCOUNT_ID>:role/SidekiqWorkIRSA"
      },
      "Action": "bedrock-agentcore:InvokeAgentRuntime",
      "Resource": "*"
    },
    {
      "Sid": "DenyNonVPCEndpointTraffic",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "bedrock-agentcore:InvokeAgentRuntime",
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "aws:SourceVpce": "vpce-0123456789abcdef0"
        }
      }
    }
  ]
}

```

### Sample Cedar Policy for AgentCore Gateway (`agentcore-policy`)

Cedar policies act as deterministic guardrails in front of tool calls:

```cedar
// Permit document reads only when run_token matches session claim
permit (
    principal,
    action == Action::"AgentTools::fetch_document",
    resource
)
when {
    context.run_token.owner == principal.tag_session_user &&
    context.request.page_count <= 50
};

// Explicitly forbid writing responses if the session status is terminated
forbid (
    principal,
    action == Action::"AgentTools::record_answer",
    resource
)
when {
    context.session_status == "TERMINATED"
};

```

---

## 6. Verification & Compliance Checklist

* [ ] **Account Posture:** Verify Service Control Policies (SCPs) explicitly deny creation of EC2, IGW, NAT Gateways, or VPC Peering in `vrm-ai`.


* [ ] **Dual Policy Alignment:** Confirm that policy updates to `InvokeAgentRuntime` are deployed simultaneously to both the runtime ARN and endpoint ARN.


* [ ] **VPC Lattice Sharing:** Ensure AWS RAM resource share is accepted in `vrm-ai` for the target ALB in `vrm-sandbox`.


* [ ] **Governance & Legal Sign-off:** Track ADR-0003 status with InfoSec and verify Legal approval for AWS AgentCore service terms prior to production.