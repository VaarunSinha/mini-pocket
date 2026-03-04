export interface Device {
  id?: string;
  name: string;
  created_at?: string;
}

/** Date components for a reminder (from AI). Used for ICS export. */
export interface ReminderDate {
  day: number;
  month: number;
  year: number;
  hour?: number;
  minute?: number;
}

export interface Note {
  id?: string;
  device_id: string;
  content: string;
  transcription?: string;
  todo_list?: string[];
  summary?: string;
  reminders?: string[];
  /** One per reminder: DD, MM, YYYY, HH, MIN from AI (for ICS). */
  reminder_dates?: (ReminderDate | null)[];
  created_at?: string;
  updated_at?: string;
}

export interface PullResult {
  device: Device;
  notes: Note[];
}

export type SyncStatus = "idle" | "syncing" | "done" | "error";

export interface DiscoveredDevice {
  url: string;
  name: string;
  /** Not broadcast; user enters on desktop and it is validated on connect. */
  code?: string;
}

/** Result of AI processing for a note. */
export interface ProcessedNoteFields {
  todo_list: string[];
  summary: string;
  reminders: string[];
  reminder_dates?: (ReminderDate | null)[];
}
