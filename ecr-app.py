import os
import boto3
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="AgentCore Runtime Microservice")

KB_ID = os.environ.get("BEDROCK_KNOWLEDGE_BASE_ID")
GUARDRAIL_ID = os.environ.get("BEDROCK_GUARDRAIL_ID")
MEMORY_ID = os.environ.get("AGENTCORE_MEMORY_ID")
REGION = os.environ.get("AWS_REGION_NAME", "us-east-1")

bedrock_agent_runtime = boto3.client("bedrock-agent-runtime", region_name=REGION)
agentcore_client = boto3.client("bedrock-agentcore", region_name=REGION)

class PromptRequest(BaseModel):
    prompt: str
    session_id: str

@app.post("/v1/agent/invoke")
async def invoke_agent(request: PromptRequest):
    try:
        # 1. Fetch persistent history from AgentCore Memory
        history = agentcore_client.list_memory_events(
            memoryId=MEMORY_ID,
            sessionId=request.session_id
        )

        # 2. Perform Knowledge Base Retrieval & Generation with Guardrail enforcement
        response = bedrock_agent_runtime.retrieve_and_generate(
            input={"text": request.prompt},
            retrieveAndGenerateConfiguration={
                "type": "KNOWLEDGE_BASE",
                "knowledgeBaseConfiguration": {
                    "knowledgeBaseId": KB_ID,
                    "modelArn": f"arn:aws:bedrock:{REGION}::foundation-model/anthropic.claude-3-5-sonnet-20240620-v1:0",
                    "generationConfiguration": {
                        "guardrailConfiguration": {
                            "guardrailId": GUARDRAIL_ID,
                            "guardrailVersion": "1"
                        }
                    }
                }
            }
        )

        output_text = response["output"]["text"]

        # 3. Save memory event to AgentCore Memory
        agentcore_client.save_memory_event(
            memoryId=MEMORY_ID,
            sessionId=request.session_id,
            event={
                "input": request.prompt,
                "output": output_text
            }
        )

        return {
            "status": "success",
            "session_id": request.session_id,
            "completion": output_text,
            "citations": response.get("citations", [])
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))