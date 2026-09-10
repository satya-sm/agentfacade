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