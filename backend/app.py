import logging
import json
from uuid import uuid4
from pathlib import Path

from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.responses import StreamingResponse
from graph import agent
from groq import APIStatusError, RateLimitError
from pydantic import BaseModel, Field
from tools.file_tool import UPLOADS_DIRECTORY

logger = logging.getLogger("uvicorn.error")

class ChatRequest(BaseModel):
    query: str = Field(min_length=1, max_length=10000)
    session_id: str = Field(default_factory=lambda: str(uuid4()))
    file_id: str | None = None

def get_delegated_agents(messages):
    agents = []

    for message in messages:
        for tool_call in getattr(message, "tool_calls", []):
            if tool_call["name"] == "task":
                agent_name = tool_call["args"].get("subagent_type")

                if agent_name and agent_name not in agents:
                    agents.append(agent_name)

    return agents

def format_event(event, data):
    return f"event: {event}\ndata: {json.dumps(data)}\n\n"

def get_text(content):
    if isinstance(content, str):
        return content

    if isinstance(content, list):
        return "".join(
            block.get("text", "") for block in content if isinstance(block, dict)
        )

    return ""

def build_message(request):
    if not request.file_id:
        return request.query

    file_id = Path(request.file_id).name
    return (
        f"{request.query}\n\n"
        f"An uploaded file is available with file_id: {file_id}. "
        "Delegate this request to the appropriate specialist and instruct it to "
        "use read_uploaded_file before answering."
    )

app = FastAPI(
    title="Deep Agentic Research Assistant",
    version="1.0.0"
)

@app.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    filename = Path(file.filename or "").name

    if not filename:
        raise HTTPException(status_code=400, detail="A filename is required.")

    file_id = f"{uuid4().hex}_{filename}"
    file_path = UPLOADS_DIRECTORY / file_id

    with file_path.open("wb") as f:
        f.write(await file.read())

    return {
        "filename": filename,
        "file_id": file_id
    }

@app.get("/")
def root():
    return {
        "message": "Deep Agentic Research Assistant Running"
    }

@app.get("/health")
def health():
    return {
        "status": "healthy"
    }

@app.post("/chat")
@app.post("/chat/")
async def chat(request: ChatRequest):
    logger.info("Processing chat request")

    try:
        result = await agent.ainvoke(
            {
                "messages": [
                    {
                        "role": "user",
                        "content": build_message(request)
                    }
                ]
            },
            config={
                "configurable": {
                    "thread_id": request.session_id
                }
            }
        )
    except RateLimitError as error:
        logger.warning("Groq rate limit reached: %s", error)
        raise HTTPException(
            status_code=429,
            detail="The AI provider rate limit has been reached. Please try again shortly."
        ) from error
    except APIStatusError as error:
        logger.warning("Groq request rejected: %s", error)
        raise HTTPException(
            status_code=413,
            detail="The conversation is too large for the configured AI model. Start a new session or send a shorter request."
        ) from error
    except Exception as error:
        logger.exception("Agent request failed")
        raise HTTPException(status_code=500, detail="Unable to process the request.") from error

    agents = get_delegated_agents(result["messages"])

    if agents:
        logger.info("Delegated to subagent(s): %s", ", ".join(agents))
    else:
        logger.warning("No subagent delegation recorded")

    return {
        "response": result["messages"][-1].content
    }

@app.post("/chat/stream")
@app.post("/chat/stream/")
async def stream_chat(request: ChatRequest):
    async def generate():
        agents = []

        try:
            async for chunk in agent.astream(
                {
                    "messages": [
                        {
                            "role": "user",
                            "content": build_message(request)
                        }
                    ]
                },
                config={
                    "configurable": {
                        "thread_id": request.session_id
                    }
                },
                stream_mode=["messages", "updates"],
                subgraphs=True,
                version="v2"
            ):
                if chunk["type"] == "messages":
                    token, metadata = chunk["data"]
                    content = get_text(token.content)
                    source = "subagent" if any(
                        item.startswith("tools:") for item in chunk["ns"]
                    ) else "main"

                    if content:
                        yield format_event("token", {
                            "content": content,
                            "source": source
                        })

                if chunk["type"] == "updates":
                    for update in chunk["data"].values():
                        if not isinstance(update, dict):
                            continue

                        for agent_name in get_delegated_agents(update.get("messages", [])):
                            if agent_name not in agents:
                                agents.append(agent_name)
                                logger.info("Delegated to subagent: %s", agent_name)
                                yield format_event("delegation", {
                                    "agent": agent_name
                                })

            logger.info("Streaming request completed")
            yield format_event("complete", {"agents": agents})
        except RateLimitError as error:
            logger.warning("Groq rate limit reached: %s", error)
            yield format_event("error", {
                "detail": "The AI provider rate limit has been reached. Please try again shortly."
            })
        except APIStatusError as error:
            logger.warning("Groq request rejected: %s", error)
            yield format_event("error", {
                "detail": "The conversation is too large for the configured AI model. Start a new session or send a shorter request."
            })
        except Exception:
            logger.exception("Streaming agent request failed")
            yield format_event("error", {
                "detail": "Unable to process the request."
            })

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no"
        }
    )
        
