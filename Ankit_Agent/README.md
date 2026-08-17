# Ankit's Agent

A Flutter client for the Deep Agentic Research Assistant FastAPI backend. It uses Riverpod for application state, persists authenticated sessions, and renders agent replies live from the backend's Server-Sent Events stream.

## Included

- Branded splash, registration, and sign-in experiences
- JWT-backed account restoration with authenticated API calls
- Streaming chat through `POST /chat/stream`
- User and active session IDs visible in the chat header
- Saved conversations and a Claude-inspired recent-conversation drawer
- A distinct dark forest / lime visual theme

## Run the backend

From the parent `backend` directory, install its dependencies and start FastAPI:

```bash
uvicorn app:app --reload --host 0.0.0.0 --port 8000
```

## Run the app

```bash
flutter pub get
flutter run
```

The default API target is `http://10.0.2.2:8000`, the Android emulator's route to the host machine. Override it for a physical device, iOS simulator, desktop, or production deployment:

```bash
flutter run --dart-define=API_BASE_URL=http://YOUR_HOST:8000
```

Use HTTPS for production. Android clear-text traffic is enabled only to support the default local FastAPI development server.
