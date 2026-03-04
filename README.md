# Mini Pocket

A **~3 hour** build inspired by [Pocket](https://heypocket.com/now) (YC W26): save and sync notes with on-device voice transcription.

**Stack:** FastAPI backend, Flutter mobile app (pocket_proxy), Tauri desktop app (pocket-desktop).

---

https://github.com/user-attachments/assets/a91e5dcf-8b4a-44e1-ba88-72ce62d6426b



## Quick start

### 1. Backend

```bash
cd backend
python -m venv venv
source venv/bin/activate   # Windows: venv\Scripts\activate
pip install -r requirements.txt
# Set env (see "Environment variables" below), then:
uvicorn app.main:app --reload
```

- API: `http://localhost:8000`
- Health: `GET /health`
- Sync: `POST /sync` with Basic auth and JSON body `{ "device": {...}, "notes": [...] }`

### 2. Pocket Proxy (Flutter app)

```bash
cd pocket_proxy
# Add Sherpa ONNX assets first (see "Sherpa ONNX models" below)
flutter pub get
flutter run
```

### 3. Pocket Desktop (Tauri + React)

```bash
cd pocket-desktop
npm install
npm run tauri dev
```

---

## Environment variables

**Backend** (use a `.env` in `backend/` or export):

| Variable              | Description                                                          |
| --------------------- | -------------------------------------------------------------------- |
| `BASIC_AUTH_USERNAME` | Username for API Basic auth (required).                              |
| `BASIC_AUTH_PASSWORD` | Password for API Basic auth.                                         |
| `DATABASE_PATH`       | Optional. Path to SQLite DB file; default: `backend/data/pocket.db`. |

**Pocket Desktop** (for “Process with AI” — todo list, summary, reminders):

| Variable           | Description                                      |
| ------------------ | ------------------------------------------------ |
| `OPENAI_API_KEY`   | Your OpenAI API key (required for AI processing). |

Example:

```bash
# Backend
export BASIC_AUTH_USERNAME=your_username
export BASIC_AUTH_PASSWORD=your_password
# optional:
export DATABASE_PATH=/path/to/pocket.db

# Pocket Desktop (for Process with AI)
export OPENAI_API_KEY=sk-your-openai-api-key
```

Then run `npm run tauri dev` from `pocket-desktop/` so the Tauri process sees the key.

---

## Sherpa ONNX models (git-ignored)

The Flutter app uses [sherpa_onnx](https://github.com/k2-fsa/sherpa-onnx?tab=readme-ov-file#some-pre-trained-asr-models-non-streaming) for on-device Whisper transcription. Model files are **large** and are **not** committed to the repo.

**Where to put them:**  
Place the Whisper **tiny.en** assets in:

```text
pocket_proxy/assets/
```

**Required files:**

- `tiny.en-encoder.int8.onnx`
- `tiny.en-decoder.int8.onnx`
- `tiny.en-tokens.txt`

You can obtain them from the [sherpa-onnx releases](https://github.com/k2-fsa/sherpa-onnx/releases) (e.g. pre-built Whisper tiny.en) or export them yourself. The app expects these exact names in `pocket_proxy/assets/`.

These paths are in `.gitignore` so the repo stays small for external viewers.

---

## Project layout

```text
.
├── backend/          # FastAPI sync API (SQLite)
├── pocket_proxy/     # Flutter app (notes + voice, syncs to backend)
├── pocket-desktop/   # Tauri + React desktop client
└── README.md         # This file
```

---
