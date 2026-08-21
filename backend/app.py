import base64
import logging
import json
import mimetypes
import os
import time
from uuid import uuid4
from pathlib import Path
from contextlib import asynccontextmanager
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, UploadFile, File, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from graph import agent, model
from groq import APIStatusError, RateLimitError
from pydantic import BaseModel, Field
from tools.file_tool import UPLOADS_DIRECTORY
from database import connection, initialize_database, utc_now
from security import (create_access_token, create_refresh_token, decode_access_token,
                      hash_password, hash_refresh_token, verify_password)

logger = logging.getLogger("uvicorn.error")

class ChatRequest(BaseModel):
    query: str = Field(min_length=1, max_length=10000)
    session_id: str = Field(default_factory=lambda: str(uuid4()))
    file_id: str | None = None

class RegisterRequest(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=8, max_length=128)

class LoginRequest(BaseModel):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=1, max_length=128)

class UpdatePasswordRequest(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)

class ForgotPasswordRequest(BaseModel):
    email: str = Field(min_length=3, max_length=254)
    new_password: str = Field(min_length=8, max_length=128)

class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=1, max_length=512)

bearer_scheme = HTTPBearer(auto_error=False)


def issue_token_pair(user_id: str, email: str) -> dict:
    refresh_token, expires_at = create_refresh_token()
    with connection() as db:
        db.execute("DELETE FROM refresh_tokens WHERE expires_at < ?", (int(time.time()),))
        db.execute(
            "INSERT INTO refresh_tokens (token_hash, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)",
            (hash_refresh_token(refresh_token), user_id, expires_at, utc_now()),
        )
    return {
        "access_token": create_access_token(user_id, email),
        "refresh_token": refresh_token,
        "token_type": "bearer",
    }

def current_user(credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)]):
    if credentials is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Authentication is required.")
    payload = decode_access_token(credentials.credentials)
    with connection() as db:
        user = db.execute("SELECT id, email, name FROM users WHERE id = ?", (payload["sub"],)).fetchone()
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User account no longer exists.")
    return dict(user)

def ensure_session(user_id: str, session_id: str, title: str | None = None) -> None:
    now = utc_now()
    with connection() as db:
        existing = db.execute("SELECT user_id FROM chat_sessions WHERE id = ?", (session_id,)).fetchone()
        if existing and existing["user_id"] != user_id:
            raise HTTPException(status_code=403, detail="This chat session belongs to another user.")
        if existing:
            db.execute("UPDATE chat_sessions SET updated_at = ? WHERE id = ?", (now, session_id))
        else:
            db.execute("INSERT INTO chat_sessions (id, user_id, title, created_at, updated_at) VALUES (?, ?, ?, ?, ?)", (session_id, user_id, title or "New chat", now, now))

def require_session(user_id: str, session_id: str) -> None:
    with connection() as db:
        session = db.execute("SELECT id FROM chat_sessions WHERE id = ? AND user_id = ?", (session_id, user_id)).fetchone()
    if session is None:
        raise HTTPException(status_code=404, detail="Chat session not found.")

def save_message(user_id: str, session_id: str, role: str, content: str) -> None:
    if not content:
        return
    now = utc_now()
    with connection() as db:
        db.execute("INSERT INTO chat_messages (id, session_id, user_id, role, content, created_at) VALUES (?, ?, ?, ?, ?, ?)", (str(uuid4()), session_id, user_id, role, content, now))
        db.execute("UPDATE chat_sessions SET updated_at = ?, title = CASE WHEN title = 'New chat' THEN ? ELSE title END WHERE id = ?", (now, content[:80], session_id))

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
    file_path = UPLOADS_DIRECTORY / file_id
    mime_type, _ = mimetypes.guess_type(file_path.name)
    if mime_type and mime_type.startswith("image/"):
        encoded = base64.b64encode(file_path.read_bytes()).decode("ascii")
        return [
            {"type": "text", "text": request.query},
            {
                "type": "image_url",
                "image_url": {"url": f"data:{mime_type};base64,{encoded}"},
            },
        ]
    return (
        f"{request.query}\n\n"
        f"An uploaded file is available with file_id: {file_id}. "
        "Delegate this request to the appropriate specialist and instruct it to "
        "use read_uploaded_file before answering."
    )

def is_image_request(request):
    if not request.file_id:
        return False
    mime_type, _ = mimetypes.guess_type(Path(request.file_id).name)
    return bool(mime_type and mime_type.startswith("image/"))

@asynccontextmanager
async def lifespan(_: FastAPI):
    initialize_database()
    yield

app = FastAPI(
    title="Deep Agentic Research Assistant",
    version="1.1.0",
    lifespan=lifespan
)
app.add_middleware(
    CORSMiddleware,
    # The app uses bearer tokens rather than cookies. Allow web deployments
    # from any HTTP(S) origin; restrict this with CORS_ORIGIN_REGEX in production
    # if the frontend domain is known.
    allow_origin_regex=os.getenv("CORS_ORIGIN_REGEX", r"https?://.+"),
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.post("/auth/register", status_code=status.HTTP_201_CREATED)
def register(request: RegisterRequest):
    email = request.email.strip().lower()
    name = request.name.strip()
    if "@" not in email or not name:
        raise HTTPException(status_code=422, detail="A name and valid email address are required.")
    user_id, now = str(uuid4()), utc_now()
    try:
        with connection() as db:
            db.execute("INSERT INTO users (id, email, name, password_hash, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)", (user_id, email, name, hash_password(request.password), now, now))
    except Exception as error:
        if "UNIQUE constraint failed" in str(error):
            raise HTTPException(status_code=409, detail="An account with this email already exists.") from error
        raise
    return {**issue_token_pair(user_id, email), "user": {"id": user_id, "name": name, "email": email}}

@app.post("/auth/login")
def login(request: LoginRequest):
    email = request.email.strip().lower()
    with connection() as db:
        user = db.execute("SELECT * FROM users WHERE email = ?", (email,)).fetchone()
    if user is None or not verify_password(request.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Incorrect email or password.")
    return {**issue_token_pair(user["id"], user["email"]), "user": {"id": user["id"], "name": user["name"], "email": user["email"]}}


@app.post("/auth/refresh")
def refresh(request: RefreshRequest):
    token_hash = hash_refresh_token(request.refresh_token)
    now_timestamp = int(time.time())
    with connection() as db:
        row = db.execute(
            "SELECT user_id FROM refresh_tokens WHERE token_hash = ? AND expires_at >= ?",
            (token_hash, now_timestamp),
        ).fetchone()
        # Rotation makes a stolen token unusable after its first use.
        db.execute("DELETE FROM refresh_tokens WHERE token_hash = ?", (token_hash,))
        if row is None:
            raise HTTPException(status_code=401, detail="Invalid or expired refresh token.")
        user = db.execute("SELECT id, email, name FROM users WHERE id = ?", (row["user_id"],)).fetchone()
        if user is None:
            raise HTTPException(status_code=401, detail="User account no longer exists.")
    return {**issue_token_pair(user["id"], user["email"]), "user": dict(user)}

@app.post("/auth/forgot-password")
def forgot_password(request: ForgotPasswordRequest):
    email = request.email.strip().lower()
    with connection() as db:
        user = db.execute("SELECT id FROM users WHERE email = ?", (email,)).fetchone()
        if user is None:
            raise HTTPException(status_code=404, detail="No account was found for that email.")
        db.execute("UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?", (hash_password(request.new_password), utc_now(), user["id"]))
        db.execute("DELETE FROM refresh_tokens WHERE user_id = ?", (user["id"],))
    return {"message": "Password updated successfully."}

@app.get("/auth/me")
def me(user: Annotated[dict, Depends(current_user)]):
    return {"user": user}

@app.patch("/auth/password", status_code=status.HTTP_204_NO_CONTENT)
def update_password(request: UpdatePasswordRequest, user: Annotated[dict, Depends(current_user)]):
    with connection() as db:
        row = db.execute("SELECT password_hash FROM users WHERE id = ?", (user["id"],)).fetchone()
        if row is None or not verify_password(request.current_password, row["password_hash"]):
            raise HTTPException(status_code=400, detail="Your current password is incorrect.")
        db.execute("UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?", (hash_password(request.new_password), utc_now(), user["id"]))
        db.execute("DELETE FROM refresh_tokens WHERE user_id = ?", (user["id"],))

@app.post("/upload", status_code=status.HTTP_201_CREATED)
async def upload_file(user: Annotated[dict, Depends(current_user)], file: UploadFile = File(...)):
    filename = Path(file.filename or "").name

    if not filename:
        raise HTTPException(status_code=400, detail="A filename is required.")

    file_id = f"{uuid4().hex}_{filename}"
    file_path = UPLOADS_DIRECTORY / file_id

    with file_path.open("wb") as f:
        f.write(await file.read())

    with connection() as db:
        db.execute("INSERT INTO uploads (id, user_id, filename, created_at) VALUES (?, ?, ?, ?)", (file_id, user["id"], filename, utc_now()))

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

@app.get("/chat/sessions")
def list_chat_sessions(user: Annotated[dict, Depends(current_user)]):
    with connection() as db:
        sessions = db.execute(
            "SELECT id, title, created_at, updated_at FROM chat_sessions WHERE user_id = ? ORDER BY updated_at DESC",
            (user["id"],),
        ).fetchall()
    return {"sessions": [dict(item) for item in sessions]}

@app.get("/chat/sessions/{session_id}/history")
def chat_history(session_id: str, user: Annotated[dict, Depends(current_user)]):
    require_session(user["id"], session_id)
    with connection() as db:
        messages = db.execute(
            "SELECT id, role, content, created_at FROM chat_messages WHERE session_id = ? AND user_id = ? ORDER BY created_at ASC",
            (session_id, user["id"]),
        ).fetchall()
    return {"session_id": session_id, "messages": [dict(item) for item in messages]}

@app.delete("/chat/sessions/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_chat_session(session_id: str, user: Annotated[dict, Depends(current_user)]):
    with connection() as db:
        deleted = db.execute("DELETE FROM chat_sessions WHERE id = ? AND user_id = ?", (session_id, user["id"])).rowcount
    if not deleted:
        raise HTTPException(status_code=404, detail="Chat session not found.")

@app.post("/chat")
@app.post("/chat/")
async def chat(request: ChatRequest, user: Annotated[dict, Depends(current_user)]):
    logger.info("Processing chat request")
    ensure_session(user["id"], request.session_id, request.query)
    if request.file_id:
        with connection() as db:
            upload = db.execute("SELECT id FROM uploads WHERE id = ? AND user_id = ?", (Path(request.file_id).name, user["id"])).fetchone()
        if upload is None:
            raise HTTPException(status_code=403, detail="Uploaded file not found or does not belong to you.")
    save_message(user["id"], request.session_id, "user", request.query)

    try:
        if is_image_request(request):
            result = await model.ainvoke(
                {"messages": [{"role": "user", "content": build_message(request)}]}
            )
            response = get_text(result.content) or str(result.content)
            save_message(user["id"], request.session_id, "assistant", response)
            return {"session_id": request.session_id, "response": response}

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
                    "thread_id": f"{user['id']}:{request.session_id}"
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
        raise HTTPException(status_code=500, detail=f"Unable to process the request: {error}") from error

    agents = [] if is_image_request(request) else get_delegated_agents(result["messages"])

    if agents:
        logger.info("Delegated to subagent(s): %s", ", ".join(agents))
    else:
        logger.warning("No subagent delegation recorded")

    response = get_text(result["messages"][-1].content) or str(result["messages"][-1].content)
    save_message(user["id"], request.session_id, "assistant", response)
    return {"session_id": request.session_id, "response": response}

@app.post("/chat/stream")
@app.post("/chat/stream/")
async def stream_chat(request: ChatRequest, user: Annotated[dict, Depends(current_user)]):
    ensure_session(user["id"], request.session_id, request.query)
    if request.file_id:
        with connection() as db:
            upload = db.execute("SELECT id FROM uploads WHERE id = ? AND user_id = ?", (Path(request.file_id).name, user["id"])).fetchone()
        if upload is None:
            raise HTTPException(status_code=403, detail="Uploaded file not found or does not belong to you.")
    save_message(user["id"], request.session_id, "user", request.query)

    async def generate():
        agents = []
        response_parts = []

        try:
            if is_image_request(request):
                result = await model.ainvoke({"messages": [{"role": "user", "content": build_message(request)}]})
                response = get_text(result.content) or str(result.content)
                save_message(user["id"], request.session_id, "assistant", response)
                yield format_event("token", {"content": response, "source": "main"})
                yield format_event("complete", {"agents": []})
                return
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
                        "thread_id": f"{user['id']}:{request.session_id}"
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
                        if source == "main":
                            response_parts.append(content)
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
            save_message(user["id"], request.session_id, "assistant", "".join(response_parts))
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
        
