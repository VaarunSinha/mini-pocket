from datetime import datetime
from typing import Any, Optional
from pydantic import BaseModel, Field


class ReminderDate(BaseModel):
    """Date components for a reminder (DD, MM, YYYY, HH, MIN). Used for ICS."""
    day: int
    month: int
    year: int
    hour: Optional[int] = None
    minute: Optional[int] = None


class Device(BaseModel):
    """One device; can have many notes."""
    id: Optional[str] = None
    name: str
    created_at: Optional[datetime] = None


class Note(BaseModel):
    """A single note belonging to a device."""
    id: Optional[str] = None
    device_id: str
    content: str
    transcription: Optional[str] = None
    todo_list: Optional[list[str]] = None
    summary: Optional[str] = None
    reminders: Optional[list[str]] = None
    reminder_dates: Optional[list[Optional[dict[str, Any]]]] = None  # one per reminder: {day, month, year, hour?, minute?}
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class SyncPayload(BaseModel):
    """Payload for sync endpoint: device + its notes."""
    device: Device
    notes: list[Note] = Field(default_factory=list)


class SyncResponse(BaseModel):
    """Response from sync: accepted device + notes (e.g. with server ids/timestamps)."""
    device: Device
    notes: list[Note] = Field(default_factory=list)


class LoginRequest(BaseModel):
    username: str
    password: str


class LoginResponse(BaseModel):
    access_token: str
