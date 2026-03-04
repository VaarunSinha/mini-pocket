# Mini Pocket — Backend (FastAPI)

Sync API for the Mini Pocket stack. Uses a **venv** for dependencies.

## Setup

```bash
# From backend/
python -m venv venv
source venv/bin/activate   # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

## Run

```bash
source venv/bin/activate
uvicorn app.main:app --reload
```

- Health: `GET http://localhost:8000/health`
- Sync: `POST http://localhost:8000/sync` with `Authorization: Bearer <token>` and JSON body `{ "device": {...}, "notes": [...] }`.
