Sure — here’s the text from the image:

First, a framing point

The two directions are not symmetric, and conflating them is where most designs go wrong.

Outbound (App → Bedrock/AgentCore): Bedrock and AgentCore are AWS-managed regional API services. You do not need network connectivity between the two VPCs for this. The Application account calls bedrock-runtime / AgentCore APIs using credentials that grant access in the Agentic account. The control plane is IAM; the network layer only determines whether the traffic leaves your VPC.

Return path (AgentCore → App account): This is the direction that actually needs network plumbing. If your agents call tools, internal APIs, databases, or an AgentCore Gateway target that lives in the Application account, you need real connectivity — PrivateLink, TGW, or an authenticated public endpoint.

Most designs need one option from the outbound list and one from the return-path list.

⸻

Most secure

Recommended: API façade in the Agentic account + PrivateLink, no Bedrock credentials in the Application account.

•⁠  ⁠Agentic account runs an internal NLB (or private API Gateway) in front of a thin invocation service, exposed as a VPC Endpoint Service.
•⁠  ⁠Application account creates an interface VPC endpoint pointing at it. Traffic never touches the internet; no route tables, no CIDR coordination, unidirectional by construction.
•⁠  ⁠The Application account holds zero bedrock:InvokeModel permissions. The façade enforces model allow-lists, guardrails, prompt/response logging, token budgets, and tenant isolation in one place you control.
•⁠  ⁠Endpoint policy restricted with aws:PrincipalOrgID; SCP on the Application account explicitly denying bedrock:* so drift is impossible.

Runner-up: cross-account AssumeRole + interface endpoints for bedrock-runtime and AgentCore. Cheaper and simpler, but the Application account now holds credentials capable of invoking models directly. Harden with a permissions boundary, sts:TagSession for tenant/app attribution, condition keys on model ARNs, and aws:SourceAccount / aws:PrincipalOrgID to close confused-deputy paths. Centralize CloudTrail and Bedrock model-invocation logs to a third (log archive) account so neither workload account can tamper with its own audit trail.

Avoid for this pattern: VPC peering or Transit Gateway as the primary answer. They grant broad bidirectional network reachability you don’t need for an API call, and they make the “Agentic account is a blast-radius boundary” claim much harder to defend.

⸻

Most cost efficient

Recommended: cross-account AssumeRole over the public service endpoints, via an existing NAT/egress path — or async decoupling via SQS/EventBridge.

Sure — text from this image:

Most cost efficient

Recommended: cross-account AssumeRole over the public service endpoints, via an existing NAT/egress path — or async decoupling via SQS/EventBridge.

•⁠  ⁠STS AssumeRole and cross-account IAM are free. No endpoint-hours, no attachment fees, no data processing charges.
•⁠  ⁠Bedrock token spend is identical regardless of account topology, and it will dominate your bill. Optimizing $20/month of endpoint cost while ignoring token routing is the wrong fight.
•⁠  ⁠For non-interactive workloads (batch enrichment, document processing, long-running agent tasks), a cross-account SQS queue or EventBridge bus is close to free at typical volumes, adds retry/DLQ for free, and eliminates the synchronous timeout problems that plague long agent invocations.

The real cost trap: if your Application account traffic currently leaves via NAT Gateway, that’s roughly $0.045/hr plus $0.045/GB processed. A VPC interface endpoint (~$0.01/hr per AZ plus ~$0.01/GB) becomes cheaper than NAT once you have meaningful volume — so the more secure option is often also the cheaper one. Run the math on your actual GB/month before assuming otherwise.

These figures are approximate, us-east-1, and change; verify against the current AWS pricing pages before committing to a design.

⸻

Easiest to deploy

Recommended: cross-account IAM role assumption, nothing else.

1.⁠ ⁠Agentic account: create BedrockInvokerRole with a trust policy naming the Application account (or aws:PrincipalOrgID), and a permissions policy scoped to specific model and AgentCore runtime ARNs.
2.⁠ ⁠Application account: attach sts:AssumeRole for that single role ARN to your task/Lambda/EKS execution role.
3.⁠ ⁠Application code: assume the role, cache credentials, instantiate the Bedrock client with them. In EKS, IRSA/Pod Identity handles this natively; in Lambda and ECS it’s a few lines.

No VPCs, no endpoints, no DNS, no CIDR negotiation. Deployable in an afternoon and easy to reason about in Terraform.

The trade-off is that traffic uses public AWS endpoints (still TLS, still on the AWS backbone once it hits the edge) and the Application account holds usable Bedrock credentials.

⸻

What I’d actually recommend

Start with cross-account AssumeRole to unblock delivery, but write it behind an internal SDK/client wrapper from day one. Add interface VPC endpoints as soon as volume justifies it — usually cost-neutral or better against NAT. Migrate to the PrivateLink façade when you need centralized guardrails, per-tenant attribution, or an auditable claim that the Application account cannot invoke models directly.

For the return path, use PrivateLink from the Agentic account into the Application account rather than TGW, unless you already run TGW as your standard network fabric.

Two things to verify before you build: current cross-account support and any account-level constraints for the specific AgentCore components you plan to use (Runtime, Gateway, Memory, Identity, Browser/Code Interpreter), and whether the Bedrock resources you want to share — knowledge bases, guardrails, prompt management, provisioned throughput, etc. — support the exact cross-account pattern you’re designing.