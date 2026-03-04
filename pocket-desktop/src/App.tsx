import { useState, useEffect } from "react";
import { createEvents } from "ics";
import { invoke } from "@tauri-apps/api/core";
import { save, message as dialogMessage } from "@tauri-apps/plugin-dialog";
import { writeTextFile } from "@tauri-apps/plugin-fs";
import type {
  Device,
  DiscoveredDevice,
  Note,
  ProcessedNoteFields,
  PullResult,
  ReminderDate,
  SyncStatus,
} from "./types";
import "./App.css";

const STORAGE_KEYS = {
  deviceUrl: "Mini Pocket_device_url",
  pairingCode: "Mini Pocket_pairing_code",
  device: "Mini Pocket_device",
  notes: "Mini Pocket_notes",
  backendUrl: "Mini Pocket_backend_url",
  username: "Mini Pocket_username",
  password: "Mini Pocket_password",
  lastSyncAt: "Mini Pocket_last_sync_at",
  completedTodos: "Mini Pocket_completed_todos",
} as const;

/** Try to format a reminder string as a readable date/time if it looks like one. */
function formatReminder(text: string): string {
  const trimmed = text.trim();
  const d = new Date(trimmed);
  if (!Number.isNaN(d.getTime())) {
    return d.toLocaleString(undefined, {
      dateStyle: "medium",
      timeStyle: "short",
    });
  }
  return trimmed;
}

/** Try to parse a reminder string into a Date for calendar export; returns null if not parseable. */
function parseReminderDate(text: string): Date | null {
  const d = new Date(text.trim());
  return Number.isNaN(d.getTime()) ? null : d;
}

/** Convert Date to ics package format [year, month, day, hour, minute] (month 1–12). */
function dateToIcsArray(d: Date): [number, number, number, number, number] {
  return [
    d.getFullYear(),
    d.getMonth() + 1,
    d.getDate(),
    d.getHours(),
    d.getMinutes(),
  ];
}

/** Build a Date from AI reminder_dates (DD, MM, YYYY, HH, MIN). Month is 1-12. */
function dateFromReminderDate(rd: ReminderDate): Date {
  return new Date(
    rd.year,
    rd.month - 1,
    rd.day,
    rd.hour ?? 9,
    rd.minute ?? 0,
  );
}

/** Build iCalendar (.ics) via ics package, show save dialog, and write file. */
async function buildIcsAndDownload(notes: Note[]): Promise<void> {
  const now = new Date();
  const tomorrow = new Date(now.getTime() + 24 * 60 * 60 * 1000);
  const defaultStart = new Date(
    tomorrow.getFullYear(),
    tomorrow.getMonth(),
    tomorrow.getDate(),
    9,
    0,
  );

  const eventAttributes: Parameters<typeof createEvents>[0] = [];

  for (const note of notes) {
    const fallbackTitle =
      note.summary ?? note.transcription?.slice(0, 80) ?? "Note";
    const reminderDates = note.reminder_dates ?? [];
    (note.reminders ?? []).forEach((r, j) => {
      const rd = reminderDates[j];
      const startDate =
        rd && typeof rd === "object" && "day" in rd && "month" in rd && "year" in rd
          ? dateFromReminderDate(rd)
          : parseReminderDate(r) ?? defaultStart;
      const title = r.trim() || fallbackTitle;
      eventAttributes.push({
        start: dateToIcsArray(startDate),
        duration: { hours: 1 },
        title,
      });
    });
  }

  if (eventAttributes.length === 0) {
    await dialogMessage(
      "No reminders to export. Process notes with AI to extract reminders first.",
      {
        title: "Export reminders",
        kind: "info",
      },
    );
    return;
  }

  const { error, value } = createEvents(eventAttributes, {
    productId: "Mini Pocket Desktop//Reminders//EN",
  });

  if (error) {
    console.error("ics createEvents error:", error);
    await dialogMessage("Failed to generate calendar file.", {
      title: "Export reminders",
      kind: "error",
    });
    return;
  }
  if (!value) {
    return;
  }

  const filePath = await save({
    defaultPath: "MiniPocket-reminders.ics",
    filters: [{ name: "iCalendar", extensions: ["ics"] }],
    title: "Save reminders to calendar",
  });

  if (filePath == null) {
    return; // User cancelled
  }

  try {
    await writeTextFile(filePath, value);
    await dialogMessage(`Saved to ${filePath}`, {
      title: "Export reminders",
      kind: "info",
    });
  } catch (e) {
    console.error("writeTextFile error:", e);
    await dialogMessage(`Could not save file: ${String(e)}`, {
      title: "Export reminders",
      kind: "error",
    });
  }
}

function todoKey(noteIndex: number, itemIndex: number): string {
  return `${noteIndex}-${itemIndex}`;
}

/** Parse "[High]", "[Medium]", "[Low]" prefix from todo/reminder string. */
function parsePriority(text: string): {
  priority: "high" | "medium" | "low" | null;
  text: string;
} {
  const t = text.trim();
  if (t.startsWith("[High]"))
    return { priority: "high", text: t.slice(6).trim() };
  if (t.startsWith("[Medium]"))
    return { priority: "medium", text: t.slice(8).trim() };
  if (t.startsWith("[Low]"))
    return { priority: "low", text: t.slice(5).trim() };
  return { priority: null, text: t };
}

function ReminderIcon() {
  return (
    <svg
      className="reminder-icon-svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      <circle cx="12" cy="12" r="10" />
      <polyline points="12 6 12 12 16 14" />
    </svg>
  );
}

function loadJson<T>(key: string): T | null {
  try {
    const s = localStorage.getItem(key);
    return s ? (JSON.parse(s) as T) : null;
  } catch {
    return null;
  }
}

function saveJson(key: string, value: unknown) {
  localStorage.setItem(key, JSON.stringify(value));
}

export default function App() {
  const [deviceUrl, setDeviceUrl] = useState(
    () => loadJson<string>(STORAGE_KEYS.deviceUrl) ?? "http://localhost:8765",
  );
  const [pairingCode, setPairingCode] = useState(
    () => loadJson<string>(STORAGE_KEYS.pairingCode) ?? "",
  );
  const [device, setDevice] = useState<Device | null>(() =>
    loadJson<Device>(STORAGE_KEYS.device),
  );
  const [notes, setNotes] = useState<Note[]>(
    () => loadJson<Note[]>(STORAGE_KEYS.notes) ?? [],
  );
  const [pullError, setPullError] = useState<string | null>(null);
  const [pullLoading, setPullLoading] = useState(false);
  const [deviceHealth, setDeviceHealth] = useState<
    "connected" | "disconnected" | null
  >(null);
  const [discovered, setDiscovered] = useState<DiscoveredDevice[]>([]);
  const [discoverLoading, setDiscoverLoading] = useState(false);
  const [discoverError, setDiscoverError] = useState<string | null>(null);
  const [processingNoteIndex, setProcessingNoteIndex] = useState<number | null>(
    null,
  );
  const [processAiStatus, setProcessAiStatus] = useState<string | null>(null);
  const [processAiError, setProcessAiError] = useState<string | null>(null);

  const [connectModalDevice, setConnectModalDevice] =
    useState<DiscoveredDevice | null>(null);
  const [connectModalCode, setConnectModalCode] = useState("");
  const [connectModalError, setConnectModalError] = useState<string | null>(
    null,
  );
  const [connectModalLoading, setConnectModalLoading] = useState(false);

  const backendUrl =
    loadJson<string>(STORAGE_KEYS.backendUrl) ?? "http://localhost:8000";

  const [username, setUsername] = useState(
    () => loadJson<string>(STORAGE_KEYS.username) ?? "",
  );
  const [password, setPassword] = useState(
    () => loadJson<string>(STORAGE_KEYS.password) ?? "",
  );
  const [lastSyncAt, setLastSyncAt] = useState<number | null>(() =>
    loadJson<number>(STORAGE_KEYS.lastSyncAt),
  );
  const [syncStatus, setSyncStatus] = useState<SyncStatus>("idle");
  const [syncError, setSyncError] = useState<string | null>(null);
  const [syncProgress, setSyncProgress] = useState(0);

  const [loginModalOpen, setLoginModalOpen] = useState(false);
  const [loginUsername, setLoginUsername] = useState("");
  const [loginPassword, setLoginPassword] = useState("");
  const [loginError, setLoginError] = useState<string | null>(null);

  const [completedTodos, setCompletedTodos] = useState<Set<string>>(() => {
    const raw = loadJson<string[]>(STORAGE_KEYS.completedTodos);
    return raw ? new Set(raw) : new Set();
  });

  useEffect(() => {
    saveJson(STORAGE_KEYS.deviceUrl, deviceUrl);
  }, [deviceUrl]);
  useEffect(() => {
    saveJson(STORAGE_KEYS.pairingCode, pairingCode);
  }, [pairingCode]);
  useEffect(() => {
    saveJson(STORAGE_KEYS.device, device);
  }, [device]);

  async function refreshDeviceHealth() {
    if (!deviceUrl || !pairingCode.trim()) {
      setDeviceHealth(null);
      return;
    }
    try {
      const ok = await invoke<boolean>("check_device_health", {
        deviceUrl,
        pairingCode: pairingCode.trim(),
      });
      setDeviceHealth(ok ? "connected" : "disconnected");
    } catch {
      setDeviceHealth("disconnected");
    }
  }

  useEffect(() => {
    refreshDeviceHealth();
  }, [deviceUrl, pairingCode]);
  useEffect(() => {
    saveJson(STORAGE_KEYS.notes, notes);
  }, [notes]);
  useEffect(() => {
    saveJson(STORAGE_KEYS.backendUrl, backendUrl);
  }, [backendUrl]);
  useEffect(() => {
    saveJson(STORAGE_KEYS.username, username);
  }, [username]);
  useEffect(() => {
    saveJson(STORAGE_KEYS.password, password);
  }, [password]);
  useEffect(() => {
    saveJson(STORAGE_KEYS.lastSyncAt, lastSyncAt);
  }, [lastSyncAt]);
  useEffect(() => {
    saveJson(STORAGE_KEYS.completedTodos, Array.from(completedTodos));
  }, [completedTodos]);

  function openConnectModal(d: DiscoveredDevice) {
    setConnectModalDevice(d);
    setConnectModalCode("");
    setConnectModalError(null);
  }

  function closeConnectModal() {
    setConnectModalDevice(null);
    setConnectModalCode("");
    setConnectModalError(null);
  }

  function handleLogout() {
    setUsername("");
    setPassword("");
    setLastSyncAt(null);
    setLoginError(null);
  }

  async function handleConnectModalSubmit() {
    if (!connectModalDevice) return;
    const code = connectModalCode.trim();
    if (code.length !== 6) {
      setConnectModalError("Enter the 6-digit pairing code.");
      return;
    }
    setConnectModalError(null);
    setConnectModalLoading(true);
    try {
      const result = await invoke<PullResult>("pull_notes", {
        deviceUrl: connectModalDevice.url,
        pairingCode: code,
      });
      setDeviceUrl(connectModalDevice.url);
      setPairingCode(code);
      setDevice(result.device);
      setNotes(result.notes);
      setLastSyncAt(null);
      setPullError(null);
      setDeviceHealth("connected");
      closeConnectModal();
    } catch (e) {
      setConnectModalError(String(e));
    } finally {
      setConnectModalLoading(false);
    }
  }

  async function handleDiscover() {
    setDiscoverError(null);
    setDiscovered([]);
    setDiscoverLoading(true);
    try {
      const list = await invoke<DiscoveredDevice[]>("discover_devices", {
        listen_secs: 5,
      });
      setDiscovered(list);
    } catch (e) {
      setDiscoverError(String(e));
    } finally {
      setDiscoverLoading(false);
    }
  }

  async function doSync(overrideUsername?: string, overridePassword?: string) {
    const authUser = overrideUsername ?? username;
    const authPass = overridePassword ?? password;
    if (!device) {
      setSyncError("No device or notes to sync.");
      return;
    }
    if (!authUser?.trim() || !authPass) {
      setSyncError("Not logged in.");
      return;
    }
    setSyncError(null);
    setSyncStatus("syncing");
    setSyncProgress(10);
    try {
      setSyncProgress(30);
      await invoke("sync_to_backend", {
        backendUrl,
        username: authUser.trim(),
        password: authPass,
        device,
        notes,
      });
      setSyncProgress(100);
      setLastSyncAt(Date.now());
      setSyncStatus("done");
      if (overrideUsername) setUsername(overrideUsername);
      if (overridePassword) setPassword(overridePassword);
      // Clear "Synced successfully." after 3s so UI returns to idle
      setTimeout(() => setSyncStatus("idle"), 3000);
    } catch (e) {
      setSyncError(String(e));
      setSyncStatus("error");
    } finally {
      setSyncProgress(0);
    }
  }

  function handleSyncNow() {
    if (username.trim() && password) {
      doSync();
    } else {
      setLoginError(null);
      setLoginModalOpen(true);
    }
  }

  async function handleLoginAndSync() {
    setLoginError(null);
    if (!loginUsername.trim() || !loginPassword) {
      setLoginError("Username and password required.");
      return;
    }
    try {
      await invoke("login", {
        backendUrl,
        username: loginUsername.trim(),
        password: loginPassword,
      });
      setUsername(loginUsername.trim());
      setPassword(loginPassword);
      setLoginModalOpen(false);
      setLoginUsername("");
      setLoginPassword("");
      doSync(loginUsername.trim(), loginPassword);
    } catch (e) {
      setLoginError(String(e));
    }
  }

  async function handlePull() {
    if (!deviceUrl || !pairingCode.trim()) return;
    setPullError(null);
    setPullLoading(true);
    try {
      const result = await invoke<PullResult>("pull_notes", {
        deviceUrl,
        pairingCode: pairingCode.trim(),
      });
      setDevice(result.device);
      setNotes(result.notes);
      setLastSyncAt(null);
      setDeviceHealth("connected");
    } catch (e) {
      setPullError(String(e));
      setDeviceHealth("disconnected");
    } finally {
      setPullLoading(false);
    }
  }

  function handleForgetDevice() {
    setDevice(null);
    setDeviceUrl("http://localhost:8765");
    setPairingCode("");
    setNotes([]);
    setDeviceHealth(null);
    setPullError(null);
    setLastSyncAt(null);
  }

  async function handleProcessWithAi(index: number) {
    const n = notes[index];
    const content = (n.transcription ?? n.content ?? "").trim();
    if (!content) return;
    setProcessAiError(null);
    setProcessAiStatus(null);
    setProcessingNoteIndex(index);
    try {
      setProcessAiStatus("Processing…");
      const referenceDate = new Date().toLocaleDateString("en-GB", {
        day: "numeric",
        month: "long",
        year: "numeric",
      });
      const result = await invoke<ProcessedNoteFields>("process_note_with_ai", {
        noteContent: content,
        referenceDate,
      });
      setNotes((prev) =>
        prev.map((note, i) =>
          i === index
            ? {
                ...note,
                todo_list: result.todo_list,
                summary: result.summary,
                reminders: result.reminders,
                reminder_dates: result.reminder_dates,
              }
            : note,
        ),
      );
    } catch (e) {
      setProcessAiError(String(e));
    } finally {
      setProcessingNoteIndex(null);
      setProcessAiStatus(null);
    }
  }

  function handleDeleteNote(index: number) {
    setNotes((prev) => prev.filter((_, i) => i !== index));
    setCompletedTodos((prev) => {
      const next = new Set<string>();
      prev.forEach((key) => {
        const [i, j] = key.split("-").map(Number);
        if (i === index) return;
        if (i > index) next.add(`${i - 1}-${j}`);
        else next.add(key);
      });
      return next;
    });
  }

  function isTodoCompleted(noteIndex: number, itemIndex: number) {
    return completedTodos.has(todoKey(noteIndex, itemIndex));
  }

  function toggleTodoCompleted(noteIndex: number, itemIndex: number) {
    setCompletedTodos((prev) => {
      const next = new Set(prev);
      const key = todoKey(noteIndex, itemIndex);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }

  const displayContent = (n: Note) =>
    n.transcription?.trim() || n.content?.trim() || "—";
  const isSynced = lastSyncAt != null && notes.length > 0;
  const hasDevice =
    device != null && deviceUrl && pairingCode.trim().length === 6;

  return (
    <main className="container">
      <header className="app-header">
        <h1>Mini Pocket Desktop</h1>
        {username.trim() && (
          <div className="header-user">
            <p className="hi-username">Hi, {username}</p>
            <button
              type="button"
              onClick={handleLogout}
              className="logout-btn"
              aria-label="Log out"
            >
              Log out
            </button>
          </div>
        )}
      </header>

      <section className="section">
        <h2>Mini Pocket Proxy</h2>
        {hasDevice ? (
          <>
            <div className="device-status-row">
              <span className="device-name">{device?.name ?? "Device"}</span>
              <span
                className={`device-health device-health--${deviceHealth ?? "unknown"}`}
              >
                {deviceHealth === "connected" && "Connected"}
                {deviceHealth === "disconnected" && "Disconnected"}
                {deviceHealth === null && "Checking…"}
              </span>
            </div>
            <div className="row device-actions">
              <button
                type="button"
                onClick={handlePull}
                disabled={pullLoading}
                aria-label="Pull latest notes"
              >
                {pullLoading ? "Pulling…" : "Pull"}
              </button>
              <button
                type="button"
                onClick={handleForgetDevice}
                className="forget-btn"
                aria-label="Forget device"
              >
                Forget device
              </button>
            </div>
          </>
        ) : (
          <>
            <p className="hint">
              Discover nearby devices, then click Connect to enter the pairing
              code and pull notes.
            </p>
            <div className="row" style={{ marginBottom: "0.5rem" }}>
              <button
                type="button"
                onClick={handleDiscover}
                disabled={discoverLoading}
                aria-busy={discoverLoading}
              >
                {discoverLoading ? "Discovering… (5s)" : "Discover devices"}
              </button>
            </div>
            {discoverError && <p className="error">{discoverError}</p>}
            {discovered.length > 0 && (
              <ul className="discovered-list">
                {discovered.map((d) => (
                  <li key={d.url} className="discovered-item">
                    <div className="discovered-info">
                      <strong>{d.name}</strong>
                      <span className="discovered-url">{d.url}</span>
                    </div>
                    <div className="discovered-actions">
                      <button
                        type="button"
                        onClick={() => openConnectModal(d)}
                        aria-label={`Connect to ${d.name}`}
                      >
                        Connect
                      </button>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </>
        )}
        {pullError && <p className="error">{pullError}</p>}
      </section>

      <section className="section">
        <div className="notes-section-header">
          <h2>Notes</h2>
          {notes.length > 0 && (
            <div className="notes-header-actions">
              {notes.some((n) => (n.reminders?.length ?? 0) > 0) && (
                <button
                  type="button"
                  className="export-calendar-btn"
                  onClick={() => buildIcsAndDownload(notes)}
                  aria-label="Export reminders to calendar"
                >
                  Export reminders to calendar
                </button>
              )}
              <button
                type="button"
                className="sync-all-btn"
                onClick={handleSyncNow}
                disabled={syncStatus === "syncing"}
                aria-label={
                  username && password
                    ? "Sync all notes"
                    : "Log in and sync all notes"
                }
              >
                Sync all notes
              </button>
            </div>
          )}
        </div>
        {notes.length === 0 ? (
          <p className="muted">
            Connect to a device and pull to see notes here.
          </p>
        ) : (
          <ul className="notes-list">
            {notes.map((n, i) => (
              <li key={n.id ?? i} className="note-card">
                <header className="note-card-header">
                  <span className="note-sync-label" aria-live="polite">
                    {isSynced ? "Synced" : "Not synced"}
                  </span>
                  <div className="note-card-actions">
                    <button
                      type="button"
                      className="process-ai-btn"
                      onClick={() => handleProcessWithAi(i)}
                      disabled={processingNoteIndex !== null}
                      aria-label="Process with AI"
                    >
                      {processingNoteIndex === i
                        ? processAiStatus || "Processing…"
                        : "Process with AI"}
                    </button>
                    {isSynced ? (
                      <span className="sync-now-synced" aria-live="polite">
                        Synced
                      </span>
                    ) : (
                      <button
                        type="button"
                        className="sync-now-btn"
                        onClick={handleSyncNow}
                        disabled={syncStatus === "syncing"}
                        aria-label={
                          username && password ? "Sync now" : "Log in and sync"
                        }
                      >
                        Sync now
                      </button>
                    )}
                    <button
                      type="button"
                      className="delete-note-btn"
                      onClick={() => handleDeleteNote(i)}
                      aria-label="Delete note"
                    >
                      Delete
                    </button>
                  </div>
                </header>
                <div className="note-content">{displayContent(n)}</div>
                <div className="note-meta">
                  {n.created_at && (
                    <span>{new Date(n.created_at).toLocaleString()}</span>
                  )}
                </div>
                <div className="note-ai">
                  <div className="note-ai-block">
                    <strong>Todo</strong>
                    {n.todo_list?.length ? (
                      <ul className="todo-list" aria-label="Todo list">
                        {n.todo_list.map((item, j) => {
                          const done = isTodoCompleted(i, j);
                          const { priority, text } = parsePriority(item);
                          return (
                            <li
                              key={j}
                              className={`todo-item ${done ? "todo-item--done" : ""}`}
                            >
                              <label className="todo-label">
                                <input
                                  type="checkbox"
                                  checked={done}
                                  onChange={() => toggleTodoCompleted(i, j)}
                                  aria-label={`Mark "${text}" as ${done ? "incomplete" : "complete"}`}
                                />
                                {priority && (
                                  <span
                                    className={`todo-priority todo-priority--${priority}`}
                                    aria-label={`Priority: ${priority}`}
                                  >
                                    {priority}
                                  </span>
                                )}
                                <span className="todo-text">{text}</span>
                              </label>
                            </li>
                          );
                        })}
                      </ul>
                    ) : (
                      <span className="muted-inline">—</span>
                    )}
                  </div>
                  <div className="note-ai-block">
                    <strong>Summary</strong>: {n.summary ?? "—"}
                  </div>
                  <div className="note-ai-block">
                    <strong>Reminders</strong>
                    {n.reminders?.length ? (
                      <ul className="reminders-list" aria-label="Reminders">
                        {n.reminders.map((r, j) => {
                          const { priority, text } = parsePriority(r);
                          const reminderLabel = text.trim();
                          const rd = n.reminder_dates?.[j];
                          const dateLabel =
                            rd &&
                            typeof rd === "object" &&
                            "day" in rd &&
                            "month" in rd &&
                            "year" in rd
                              ? formatReminder(
                                  dateFromReminderDate(rd as ReminderDate).toISOString(),
                                )
                              : null;
                          return (
                            <li key={j} className="reminder-item">
                              <span className="reminder-icon" aria-hidden>
                                <ReminderIcon />
                              </span>
                              {priority && (
                                <span
                                  className={`reminder-priority reminder-priority--${priority}`}
                                  aria-label={`Priority: ${priority}`}
                                >
                                  {priority}
                                </span>
                              )}
                              <span className="reminder-text">
                                {reminderLabel}
                                {dateLabel && (
                                  <span className="reminder-date-suffix">
                                    {" "}
                                    — {dateLabel}
                                  </span>
                                )}
                              </span>
                            </li>
                          );
                        })}
                      </ul>
                    ) : (
                      <span className="muted-inline">—</span>
                    )}
                  </div>
                </div>
              </li>
            ))}
          </ul>
        )}
        {syncStatus === "syncing" && (
          <div className="progress-wrap">
            <progress value={syncProgress} max={100} aria-label="Syncing" />
          </div>
        )}
        {syncStatus === "done" && (
          <p className="success">Synced successfully.</p>
        )}
        {(syncError || syncStatus === "error") && (
          <p className="error">{syncError}</p>
        )}
        {processAiError && <p className="error">{processAiError}</p>}
      </section>

      {connectModalDevice && (
        <dialog
          open
          className="modal-dialog"
          aria-labelledby="connect-modal-title"
        >
          <div className="modal">
            <h2 id="connect-modal-title">
              Connect to {connectModalDevice.name}
            </h2>
            <p className="hint">
              Enter the 6-digit pairing code shown on the device. It will be
              validated before pulling.
            </p>
            <label className="label">
              Pairing code
              <input
                type="text"
                inputMode="numeric"
                autoComplete="off"
                maxLength={6}
                value={connectModalCode}
                onChange={(e) =>
                  setConnectModalCode(
                    e.target.value.replace(/\D/g, "").slice(0, 6),
                  )
                }
                placeholder="000000"
                disabled={connectModalLoading}
              />
            </label>
            {connectModalError && <p className="error">{connectModalError}</p>}
            <div className="modal-actions">
              <button
                type="button"
                onClick={closeConnectModal}
                disabled={connectModalLoading}
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConnectModalSubmit}
                disabled={
                  connectModalLoading || connectModalCode.trim().length !== 6
                }
              >
                {connectModalLoading ? "Connecting…" : "Connect & pull"}
              </button>
            </div>
          </div>
        </dialog>
      )}

      {loginModalOpen && (
        <dialog open className="modal-dialog" aria-labelledby="login-title">
          <div className="modal">
            <h2 id="login-title">Log in to sync</h2>
            <label className="label">
              Username
              <input
                type="text"
                value={loginUsername}
                onChange={(e) => setLoginUsername(e.target.value)}
                placeholder="Username"
                autoComplete="username"
                aria-required="true"
              />
            </label>
            <label className="label">
              Password
              <input
                type="password"
                value={loginPassword}
                onChange={(e) => setLoginPassword(e.target.value)}
                placeholder="Password"
                autoComplete="current-password"
                aria-required="true"
              />
            </label>
            {loginError && <p className="error">{loginError}</p>}
            <div className="modal-actions">
              <button
                type="button"
                onClick={() => {
                  setLoginModalOpen(false);
                  setLoginError(null);
                }}
              >
                Cancel
              </button>
              <button type="button" onClick={handleLoginAndSync}>
                Log in & sync
              </button>
            </div>
          </div>
        </dialog>
      )}
    </main>
  );
}
