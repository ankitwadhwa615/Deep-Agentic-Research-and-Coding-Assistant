# Ankit's Agent

Ankit's Agent is a portfolio-grade AI assistant built by Ankit Wadhwa to demonstrate practical AI application development, agent orchestration, multimodal interaction, and production-minded full-stack engineering.

It combines a Flutter client with a FastAPI service and a LangGraph/Deep Agents orchestration layer. Users can research topics, analyze uploaded documents and images, ask coding questions, and maintain authenticated multi-turn conversations.

## Portfolio Positioning

This project demonstrates the work of an AI Developer who can:

- Design and integrate LLM-powered product experiences.
- Build tool-using, delegation-first agent workflows.
- Connect multimodal model inputs with file and image upload pipelines.
- Build secure authenticated APIs and persistent conversation storage.
- Ship a cross-platform Flutter interface with responsive state handling.
- Diagnose and improve real-world streaming, validation, and browser issues.

## Core Features

- Email/password registration and login with JWT authentication.
- Inline form validation and disabled states for invalid auth input.
- Password-change endpoint plus a password-reset API endpoint.
- Persistent user sessions using Flutter `shared_preferences`.
- New conversations, saved sessions, and message history.
- Research, coding, review, and general-purpose specialist agents.
- Delegation status updates during agent execution.
- Server-Sent Events (SSE) responses with live delegation status in the Flutter client.
- A non-streaming JSON chat endpoint for integrations or clients that do not use SSE.
- Upload support for UTF-8 text-based files, PDFs, and images.
- Image previews in chat and direct vision-model analysis.
- Lightweight Markdown-style rendering for headings, bold, italics, bullets, and dividers.
- SQLite persistence for users, sessions, messages, and uploads.
- CORS configuration for web deployments.

## Architecture

```text
Flutter Client
  ├─ Screens: authentication, chat, splash/session gate
  ├─ Controllers: auth and chat state via Riverpod ChangeNotifier providers
  ├─ API Client: JSON, multipart upload, streaming/non-streaming chat
  └─ Platform handling: Web, iOS, Android, desktop file selection
             │
             ▼
FastAPI Backend
  ├─ Auth routes: register, login, current user, password reset
  ├─ Chat routes: sessions, history, JSON chat, SSE streaming chat
  ├─ Upload route: authenticated multipart file storage
  ├─ SQLite database: users, sessions, messages, upload metadata
  └─ CORS and bearer-token security middleware
             │
             ▼
Agent Runtime
  ├─ LangGraph checkpointed execution
  ├─ Deep Agents orchestration
  ├─ Researcher agent with web search and file reading
  ├─ Coder agent for implementation and debugging tasks
  ├─ Reviewer agent for quality and verification tasks
  └─ Vision-capable model path for uploaded images
```

## Technology Stack

### Frontend

- Flutter and Dart
- Flutter Riverpod state management
- `http` for REST and streaming requests
- `shared_preferences` for local auth persistence
- `file_picker` and `image_picker` for attachments
- Firebase Core initialization and Firebase Hosting configuration
- Responsive Material 3 UI

### Backend

- Python 3
- FastAPI and Uvicorn
- Pydantic request validation
- SQLite with a small context-managed data layer
- JWT bearer authentication
- PBKDF2-SHA256 password hashing with per-password salts
- Multipart upload handling
- CORS middleware

### AI and Agent Layer

- LangChain
- LangGraph
- Deep Agents
- Groq-hosted chat models
- Tavily web search
- Specialist subagents for research, coding, and review
- Vision-capable model input for image analysis

## Repository Layout

```text
.
├── backend/
│   ├── app.py                 # FastAPI routes and request orchestration
│   ├── graph.py               # Main model and Deep Agent configuration
│   ├── agents/                # Researcher, coder, and reviewer subagents
│   ├── tools/                 # Search and uploaded-file tools
│   ├── database.py            # SQLite schema and connection helper
│   ├── security.py            # Password and JWT helpers
│   └── requirements.txt       # Python dependencies
├── frontend/
│   ├── lib/screens/           # Auth, splash, and chat screens
│   ├── lib/controllers/       # Auth and chat state
│   ├── lib/services/          # API client
│   ├── lib/core/              # Providers and platform API defaults
│   ├── lib/models/            # Frontend data models
│   └── pubspec.yaml           # Flutter dependencies
└── README.md
```

## API Surface

### Authentication

- `POST /auth/register`
- `POST /auth/login`
- `POST /auth/refresh`
- `GET /auth/me`
- `PATCH /auth/password`
- `POST /auth/forgot-password`

### Files and Chat

- `POST /upload`
- `GET /chat/sessions`
- `GET /chat/sessions/{session_id}/history`
- `DELETE /chat/sessions/{session_id}`
- `POST /chat`
- `POST /chat/stream`

`/health` is available for service checks. All chat, session, history, and upload requests require a bearer token. Login, registration, and token refresh return an access/refresh token pair; refresh tokens are stored server-side only as keyed hashes and rotated on use.

## Local Development

### 1. Start the backend

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app:app --reload --host 0.0.0.0 --port 8000
```

Configure the required provider credentials in `backend/.env`, for example:

```env
GROQ_API_KEY=your_groq_api_key
TAVILY_API_KEY=your_tavily_api_key
JWT_SECRET=replace-with-a-long-random-secret
```

Optional backend configuration includes `GROQ_TEXT_MODEL`, `GROQ_VISION_MODEL`, `ACCESS_TOKEN_EXPIRES_MINUTES`, `REFRESH_TOKEN_EXPIRES_DAYS`, and `CORS_ORIGIN_REGEX`. Set `JWT_SECRET` in every persistent deployment; without it, a restart invalidates existing tokens.

### 2. Start Flutter

```bash
cd frontend
flutter pub get
flutter run
```

Override the API URL when running on a physical device, emulator, or deployed environment:

```bash
flutter run --dart-define=API_BASE_URL=http://YOUR_HOST:8000
```

The checked-in default API URL targets the deployed Render service. Firebase configuration is included for Android, iOS, macOS, Web, and Windows; use a Firebase configuration for your own project before distributing a fork. For production, use HTTPS and configure `CORS_ORIGIN_REGEX` on the backend.

## Design Notes

- The Flutter client uses the SSE endpoint for incremental responses; `/chat` provides the equivalent non-streaming JSON response.
- Uploaded images are sent to the vision-capable model as multimodal content.
- PDFs are text-extracted with `pypdf`; text-based files are decoded as UTF-8. Other binary file types can be uploaded but are not meaningfully parsed by the current file-reading tool.
- Conversation checkpoints use an in-memory LangGraph saver; durable conversation history is stored in SQLite.

## Security Notes

- Passwords are stored as hashes, never as plaintext.
- Authenticated resources are scoped to the current user.
- Upload ownership is checked before a file is used in a chat request.
- Do not commit `.env` files, API keys, production databases, or uploaded user files.
- The current password-reset API directly updates a password after email lookup, and its UI trigger is not enabled. A production deployment should replace it with a time-limited, email-delivered reset token.

## Portfolio Summary

Ankit's Agent is designed to show how an AI Developer turns LLM capabilities into a usable product: a polished cross-platform client, validated API boundaries, persistent user workflows, specialist agent routing, multimodal inputs, and practical operational safeguards.
