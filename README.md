
Echo

Your AI best friend. Your research partner. One memory that grows with you.

Echo is an AI companion designed around two things most AI assistants struggle to balance:

Human conversation and trustworthy research.

Instead of acting like a generic chatbot, Echo is built to feel like a long-term digital companion — one that remembers context, adapts to how you communicate, researches deeply when needed, and is honest when it doesn't know something.

---

What is Echo?

Echo is an AI companion and research partner built for people who want more than short-lived conversations.

It combines:

- Long-term memory
- Natural, personality-driven conversations
- Deep research
- Context-aware responses
- Offline-first capabilities
- Transparent uncertainty
- Privacy-focused architecture
- A communication style that feels natural rather than robotic

The goal is simple:

«Build an AI that feels like someone you can actually talk to — while still being useful when you need to get things done.»

---

Core Philosophy

1. Don't fake certainty

If Echo cannot find enough reliable information, it should say so.

No invented sources.
No pretending a search was performed when it wasn't.
No confidently making things up just to keep the conversation flowing.

Echo is designed around:

"I don't know" being better than a wrong answer.

---

2. Remember the relationship

Most AI conversations feel temporary.

Echo is designed to remember important context over the long term.

Its memory system is intended to support:

- Personal preferences
- Previous conversations
- Important facts
- User-specific context
- Evolving interests
- Contradictory information
- Long-term conversational continuity

Memory should not simply overwrite old information blindly.

When information conflicts, Echo can preserve the history and handle the contradiction instead of silently destroying the previous context.

---

3. Talk naturally

Echo isn't designed to sound like a corporate assistant.

It can adapt to the user's communication style, including:

- Casual English
- Hinglish
- Slang
- Short messages
- Lowercase writing
- Regional conversational styles

The objective isn't to make Echo "sound young."

The objective is to make conversations feel natural.

---

Features

AI Companion

Have conversations that aren't limited to rigid assistant commands.

Echo is designed to support:

- Casual conversations
- Brainstorming
- Personal discussions
- Ideas and projects
- Everyday questions
- Long-running conversations

Research Partner

Echo can go beyond simple question answering.

When research capabilities are available, it is designed to:

1. Understand the question
2. Search for relevant information
3. Compare sources
4. Reason over the findings
5. Identify uncertainty
6. Give the user a clear answer

If sufficient evidence cannot be found, Echo should communicate that limitation instead of fabricating an answer.

Long-Term Memory

Echo uses a memory architecture designed around persistent context.

The system aims to distinguish between:

- Temporary conversation context
- Long-term memories
- Important user information
- Potentially outdated information
- Contradictory memories

Offline-First

Echo is being designed with offline-first principles.

Local capabilities can remain available when network connectivity is unavailable.

When Echo is offline, it should tell the user rather than pretending that it performed an online operation.

Streaming Responses

Responses are streamed progressively instead of appearing all at once.

Echo uses natural word/phrase-level streaming rather than an artificial letter-by-letter typing effect.

---

Architecture

Echo is built around a client + backend architecture.

┌───────────────────────────┐
│          Echo App         │
│       Flutter / Dart      │
└─────────────┬─────────────┘
              │
              ▼
┌───────────────────────────┐
│       Local Storage       │
│          SQLite           │
│       Offline Memory      │
└─────────────┬─────────────┘
              │
              │ Sync / API
              ▼
┌───────────────────────────┐
│       FastAPI Backend     │
│      Authentication       │
│      AI Request Proxy     │
│      Memory Services      │
└─────────────┬─────────────┘
              │
              ▼
┌───────────────────────────┐
│        AI Provider        │
│      NVIDIA LLM API       │
└───────────────────────────┘

Current technology direction

Layer| Technology
Mobile| Flutter
Language| Dart
Backend| FastAPI
Local database| SQLite
Authentication| Firebase Authentication
Cloud services| Firebase
AI| NVIDIA LLM API
Architecture| Offline-first + cloud
API communication| REST / streaming

---

Privacy

Privacy is a core design principle of Echo.

The architecture is being designed to minimize unnecessary data exposure and keep sensitive functionality behind controlled backend boundaries.

The project also avoids embedding sensitive AI credentials directly inside the mobile application.

Instead:

Echo App
   ↓
Secure Backend
   ↓
AI Provider

## Running the AI backend

The AI provider key must stay on the server. Set `NVIDIA_CHAT_KEY` in the backend or
serverless function environment; never put it in Flutter code or commit it to GitHub.

For a local backend, run it from the repository root:

```powershell
python -m uvicorn backend.main:app --reload --port 8000
```

When the backend is deployed remotely, build the Flutter app with its HTTPS base URL:

```powershell
flutter build web --release --dart-define=ECHO_API_URL=https://your-backend.example.com --base-href "/echo-ai/"
```

The GitHub Pages workflow deploys the static web app only. It does not expose server
environment variables, so the backend must be deployed separately with
`NVIDIA_CHAT_KEY` configured.

## Firebase deployment

Echo uses a Firebase HTTPS Function as its secure AI gateway. The NVIDIA key is
stored in Firebase Secret Manager and is never included in Flutter builds or Git.
The Firebase project must use the Blaze plan because Cloud Functions and Secret
Manager require billing to be enabled.

From the repository root, after enabling Blaze:

```powershell
firebase use echo-41c5d-506717
firebase functions:secrets:set NVIDIA_CHAT_KEY
flutter build web --release
firebase deploy --only functions,hosting,firestore
```

The Hosting rewrite sends `/api/chat` and `/api/extract-memory` to the
`asia-south1` `echo_api` function, so web users do not need a local server.

API credentials remain on the server side rather than being shipped with the client application.

---

Project Structure

The exact structure may evolve as Echo develops, but the intended architecture is approximately:

echo/
│
├── android/
├── ios/
├── lib/
│   ├── core/
│   ├── models/
│   ├── services/
│   ├── memory/
│   ├── chat/
│   ├── research/
│   └── ui/
│
├── backend/
│   ├── api/
│   ├── services/
│   ├── memory/
│   └── models/
│
├── test/
│
└── README.md

---

Development Status

Echo is currently under active development.

The project is being built incrementally, with the architecture evolving alongside experimentation with:

- AI models
- Memory systems
- Research workflows
- Offline functionality
- Conversational UX
- Privacy
- Long-term personalization

Expect things to change.

---

Roadmap

Phase 1 — Foundation

- [x] Flutter application
- [x] AI API integration
- [x] FastAPI backend
- [x] Firebase authentication
- [x] Local SQLite storage
- [x] Streaming responses

Phase 2 — Memory

- [x] Local memory foundation
- [ ] Long-term memory engine
- [ ] Memory importance scoring
- [ ] Memory contradiction handling
- [ ] Memory trust system
- [ ] Cloud synchronization

Phase 3 — Research

- [ ] Deep research workflow
- [ ] Multi-source search
- [ ] Source comparison
- [ ] Evidence-aware answers
- [ ] Research summaries
- [ ] Uncertainty detection

Phase 4 — Companion Intelligence

- [ ] Better personality adaptation
- [ ] Communication-style adaptation
- [ ] Long-term relationship context
- [ ] Better contextual recall
- [ ] More natural conversational behavior

Phase 5 — Scale

- [ ] Production infrastructure
- [ ] Performance optimization
- [ ] Advanced privacy controls
- [ ] Multi-platform expansion
- [ ] Public release

---

Design Principles

Echo follows a few simple rules:

Be useful.
Be honest.
Remember what matters.
Don't pretend.
Don't be robotic.
Don't expose unnecessary data.

These principles influence both the AI behavior and the underlying architecture.

---

Why Echo?

The AI market has plenty of assistants.

It also has plenty of AI companions.

Echo is exploring the space between the two.

An AI shouldn't have to choose between:

"I can talk to you."

and

"I can actually help you."

Echo is an attempt to build both into the same experience.

---

Contributing

Echo is currently primarily developed as an independent project.

As the project matures, contribution guidelines will be added for developers interested in helping with:

- AI systems
- Flutter development
- Backend engineering
- Memory architecture
- Research systems
- UI/UX
- Privacy engineering

---

Disclaimer

Echo is an experimental software project under active development.

AI-generated information can be incorrect. Research results should be independently verified when accuracy is important.

---

License

License information will be added before public distribution.

---

Built with curiosity.

Echo

An AI companion that remembers — and a research partner that doesn't pretend to know everything.