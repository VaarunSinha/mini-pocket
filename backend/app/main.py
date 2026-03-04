from contextlib import contextmanager
from typing import Annotated

from dotenv import load_dotenv

from fastapi import Depends, FastAPI

load_dotenv()

from app.auth import get_current_username
from app.db import get_connection, save_sync
from app.models import SyncPayload, SyncResponse

app = FastAPI(title="Mini Pocket Sync", version="0.1.0")


@contextmanager
def get_db():
    """Yield a DB connection and close it on exit."""
    conn = get_connection()
    try:
        yield conn
    finally:
        conn.close()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/auth/login")
def login(username: Annotated[str, Depends(get_current_username)]):
    """Validate HTTP Basic credentials. Returns 200 if valid, 401 otherwise."""
    return {"ok": True, "username": username}


@app.post("/sync")
def sync(
    payload: SyncPayload,
    username: Annotated[str, Depends(get_current_username)],
) -> SyncResponse:
    """Persist device and notes for the authenticated user, then return the same payload."""
    with get_db() as conn:
        save_sync(conn, username, payload.device, payload.notes)
    return SyncResponse(device=payload.device, notes=payload.notes)
