"""SQLite storage for devices and notes, keyed by username."""

import json
import os
import sqlite3
import uuid
from pathlib import Path

from app.models import Device, Note

# Database file in backend directory (or use env DATABASE_PATH)
_DEFAULT_DB_PATH = Path(__file__).resolve().parent.parent / "data" / "pocket.db"


def _get_db_path() -> Path:
    path = os.environ.get("DATABASE_PATH")
    if path:
        return Path(path)
    return _DEFAULT_DB_PATH


def get_connection() -> sqlite3.Connection:
    """Return a connection to the SQLite database. Creates DB dir and tables if needed."""
    db_path = _get_db_path()
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    _init_schema(conn)
    return conn


def _init_schema(conn: sqlite3.Connection) -> None:
    """Create tables if they do not exist."""
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS devices (
            username TEXT PRIMARY KEY,
            device_id TEXT,
            name TEXT NOT NULL,
            created_at TEXT
        );
        CREATE TABLE IF NOT EXISTS notes (
            id TEXT NOT NULL,
            username TEXT NOT NULL,
            device_id TEXT NOT NULL,
            content TEXT NOT NULL DEFAULT '',
            transcription TEXT,
            todo_list TEXT,
            summary TEXT,
            reminders TEXT,
            reminder_dates TEXT,
            created_at TEXT,
            updated_at TEXT,
            PRIMARY KEY (username, id)
        );
    """)
    try:
        conn.execute("ALTER TABLE notes ADD COLUMN reminder_dates TEXT")
    except sqlite3.OperationalError:
        pass  # column already exists
    conn.commit()


def _row_to_device(row: sqlite3.Row) -> Device:
    return Device(
        id=row["device_id"] or None,
        name=row["name"],
        created_at=row["created_at"],
    )


def _row_to_note(row: sqlite3.Row) -> Note:
    todo_list = None
    if row["todo_list"]:
        try:
            todo_list = json.loads(row["todo_list"])
        except (json.JSONDecodeError, TypeError):
            pass
    reminders = None
    if row["reminders"]:
        try:
            reminders = json.loads(row["reminders"])
        except (json.JSONDecodeError, TypeError):
            pass
    reminder_dates = None
    if row.get("reminder_dates"):
        try:
            reminder_dates = json.loads(row["reminder_dates"])
        except (json.JSONDecodeError, TypeError):
            pass
    return Note(
        id=row["id"],
        device_id=row["device_id"],
        content=row["content"] or "",
        transcription=row["transcription"],
        todo_list=todo_list,
        summary=row["summary"],
        reminders=reminders,
        reminder_dates=reminder_dates,
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


def save_sync(conn: sqlite3.Connection, username: str, device: Device, notes: list[Note]) -> None:
    """Persist device and notes for this user. Replaces existing data for the user."""
    device_id = device.id or ""
    created_at = device.created_at.isoformat() if device.created_at else None

    conn.execute(
        """
        INSERT INTO devices (username, device_id, name, created_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(username) DO UPDATE SET
            device_id = excluded.device_id,
            name = excluded.name,
            created_at = excluded.created_at
        """,
        (username, device_id, device.name, created_at),
    )

    conn.execute("DELETE FROM notes WHERE username = ?", (username,))

    for n in notes:
        note_id = n.id or uuid.uuid4().hex
        n_created = n.created_at.isoformat() if n.created_at else None
        n_updated = n.updated_at.isoformat() if n.updated_at else None
        todo_json = json.dumps(n.todo_list) if n.todo_list else None
        reminders_json = json.dumps(n.reminders) if n.reminders else None
        reminder_dates_json = json.dumps(n.reminder_dates) if n.reminder_dates else None
        conn.execute(
            """
            INSERT INTO notes (id, username, device_id, content, transcription, todo_list, summary, reminders, reminder_dates, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                note_id,
                username,
                n.device_id,
                n.content,
                n.transcription,
                todo_json,
                n.summary,
                reminders_json,
                reminder_dates_json,
                n_created,
                n_updated,
            ),
        )
    conn.commit()


def load_sync(conn: sqlite3.Connection, username: str) -> tuple[Device | None, list[Note]]:
    """Load stored device and notes for this user. Returns (device, notes) or (None, [])."""
    row = conn.execute(
        "SELECT device_id, name, created_at FROM devices WHERE username = ?",
        (username,),
    ).fetchone()
    if not row:
        return None, []

    device = _row_to_device(row)

    cursor = conn.execute(
        "SELECT id, device_id, content, transcription, todo_list, summary, reminders, reminder_dates, created_at, updated_at FROM notes WHERE username = ? ORDER BY created_at",
        (username,),
    )
    notes = [_row_to_note(r) for r in cursor.fetchall()]
    return device, notes
