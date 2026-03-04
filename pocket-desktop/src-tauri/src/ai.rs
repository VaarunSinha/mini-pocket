//! AI processing for notes: todo list, summary, reminders via OpenAI API (gpt-4o).
//! API key is loaded from OPENAI_API_KEY env var.

use serde::{Deserialize, Serialize};

const OPENAI_API_URL: &str = "https://api.openai.com/v1/chat/completions";
const MODEL: &str = "gpt-4o";
const ENV_OPENAI_API_KEY: &str = "OPENAI_API_KEY";

/// System prompt describing the required JSON shape for ProcessedNoteFields.
const SYSTEM_PROMPT: &str = r#"You extract structured data from notes. Respond with a single JSON object only, no markdown or explanation, with these exact keys:

- "todo_list": array of strings. Each string MUST use this exact format: "[Priority] Assignee: task description"
  * Priority: one of [High], [Medium], [Low]. Use [High] ONLY for truly urgent/critical items (e.g. "production incident", "ASAP", "tonight", "drop everything"). Use [Medium] for most tasks and normal deadlines. Use [Low] for "when you get a chance", "no rush", or optional items. Do NOT default to High—most items should be [Medium].
  * Assignee: "Myself" if the note-taker does it (e.g. "I need to...", "I have to..."); or the person's name if someone else (e.g. "Arjun do this" → "Arjun").
  * Example: "[High] Myself: Production deployment tonight", "[Medium] Arjun: Take the authentication bug", "[Medium] Preya: Dashboard pull request", "[Low] Myself: Review when free".
  Empty array if no actionable todos.

- "summary": string (one short paragraph).

- "reminders": array of strings. Each string MUST use: "[Priority] Assignee: event/action description only". Do NOT include the date or time in the reminder text (e.g. no "4 March 2026", "20:00", "at 8pm")—put those only in reminder_dates. The reminder text is just the action: e.g. "Myself: Handle the production deployment tonight", "Myself: Update the product roadmap by 20th March". Same priority rules: [High] only for urgent/time-sensitive; [Medium] for most; [Low] for flexible. Never leave reminders empty when the note mentions any future date, deadline, or meeting.

- "reminder_dates": array of objects (same length as reminders). For each reminder, provide the date/time as numbers using the REFERENCE DATE (today) when interpreting relative phrases. Each object has: "day" (1-31), "month" (1-12), "year" (e.g. 2026), "hour" (0-23, 24h), "minute" (0-59). Use the reference date for context: "tonight" = same day, hour 20 (8pm), minute 0; "today" = same day 9:00; "tomorrow" = next calendar day 9:00; "20th March" or "by 20th March" = day 20, month 3, year from reference, hour 9, minute 0; "Friday" = the next Friday from reference. If a reminder has no clear date, use null for that entry. Always output reminder_dates with one entry per reminder (object or null)."#;

const USER_PROMPT_PREFIX: &str = r#"Extract from this note (voice memo or text): todo_list, summary, reminders, and reminder_dates.
CRITICAL: Each todo and reminder must start with [High], [Medium], or [Low], then assignee (Myself or name), then ": ", then the content. In reminder strings, omit all dates and times—only the event description (e.g. "Handle the production deployment tonight"). Put the actual date/time in reminder_dates only. Use the reference date below for "tonight", "tomorrow", "20th March", etc.

Note:
---
"#;
const USER_PROMPT_SUFFIX: &str = "\n---";

/// Date components for one reminder (DD, MM, YYYY, HH, MIN). Used for ICS export.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReminderDate {
    pub day: u32,
    pub month: u32,
    pub year: u32,
    #[serde(default)]
    pub hour: Option<u32>,
    #[serde(default)]
    pub minute: Option<u32>,
}

/// Result of AI processing for one note.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProcessedNoteFields {
    #[serde(rename = "todo_list")]
    pub todo_list: Vec<String>,
    pub summary: String,
    pub reminders: Vec<String>,
    /// One entry per reminder: date components (day, month, year, hour, minute) or null.
    #[serde(rename = "reminder_dates", default)]
    pub reminder_dates: Vec<Option<ReminderDate>>,
}

/// Holds shared HTTP client for OpenAI requests.
pub struct AiModelState {
    pub client: reqwest::Client,
}

impl AiModelState {
    pub fn new() -> Self {
        Self {
            client: reqwest::Client::new(),
        }
    }
}

#[derive(Serialize)]
struct OpenAIMessage {
    role: String,
    content: String,
}

#[derive(Serialize)]
struct OpenAIRequest {
    model: String,
    messages: Vec<OpenAIMessage>,
    #[serde(skip_serializing_if = "Option::is_none")]
    response_format: Option<serde_json::Value>,
}

#[derive(Deserialize)]
struct OpenAIChoice {
    message: OpenAIMessageResponse,
}

#[derive(Deserialize)]
struct OpenAIMessageResponse {
    content: Option<String>,
}

#[derive(Deserialize)]
struct OpenAIResponse {
    choices: Vec<OpenAIChoice>,
}

/// Process note content with OpenAI gpt-4o; returns todo_list, summary, reminders, reminder_dates.
/// reference_date: today's date for the AI to use when resolving "tonight", "tomorrow", "20th March", etc. (e.g. "4 March 2026").
/// Requires OPENAI_API_KEY to be set in the environment.
pub async fn process_note_with_ai(
    state: tauri::State<'_, AiModelState>,
    note_content: String,
    reference_date: Option<String>,
    _model_id: Option<String>,
) -> Result<ProcessedNoteFields, String> {
    let api_key = std::env::var(ENV_OPENAI_API_KEY)
        .map_err(|_| format!("{} is not set", ENV_OPENAI_API_KEY))?;
    let api_key = api_key.trim();
    if api_key.is_empty() {
        return Err(format!("{} is empty", ENV_OPENAI_API_KEY));
    }

    let content = note_content.trim();
    let content = if content.is_empty() {
        "(empty note)"
    } else {
        content
    };
    let ref_line = reference_date
        .as_deref()
        .filter(|s| !s.is_empty())
        .map(|s| format!("Reference date (today): {}.\n\n", s.trim()))
        .unwrap_or_default();
    let user_content = format!(
        "{}{}{}{}",
        ref_line,
        USER_PROMPT_PREFIX,
        content,
        USER_PROMPT_SUFFIX
    );

    let body = OpenAIRequest {
        model: MODEL.to_string(),
        messages: vec![
            OpenAIMessage {
                role: "system".to_string(),
                content: SYSTEM_PROMPT.to_string(),
            },
            OpenAIMessage {
                role: "user".to_string(),
                content: user_content,
            },
        ],
        response_format: Some(serde_json::json!({ "type": "json_object" })),
    };

    let res = state
        .client
        .post(OPENAI_API_URL)
        .header("Authorization", format!("Bearer {}", api_key))
        .header("Content-Type", "application/json")
        .json(&body)
        .send()
        .await
        .map_err(|e| e.to_string())?;

    if !res.status().is_success() {
        let status = res.status();
        let text = res.text().await.unwrap_or_else(|_| String::new());
        return Err(format!("OpenAI API error {}: {}", status, text));
    }

    let parsed: OpenAIResponse = res.json().await.map_err(|e| e.to_string())?;
    let text = parsed
        .choices
        .first()
        .and_then(|c| c.message.content.as_deref())
        .ok_or_else(|| "Empty response from OpenAI".to_string())?;

    let json_str = extract_json(text)?;
    let parsed: ProcessedNoteFields =
        serde_json::from_str(json_str).map_err(|e| format!("Invalid JSON: {}", e))?;

    let reminders: Vec<String> = parsed
        .reminders
        .into_iter()
        .filter(|s| !s.is_empty())
        .collect();
    let n = reminders.len();
    let mut reminder_dates = parsed.reminder_dates;
    reminder_dates.truncate(n);
    while reminder_dates.len() < n {
        reminder_dates.push(None);
    }

    Ok(ProcessedNoteFields {
        todo_list: parsed
            .todo_list
            .into_iter()
            .filter(|s| !s.is_empty())
            .collect(),
        summary: parsed.summary.trim().to_string(),
        reminders,
        reminder_dates,
    })
}

fn extract_json(s: &str) -> Result<&str, String> {
    let s = s.trim();
    if let Some(rest) = s.strip_prefix("```json") {
        let end = rest.find("```").unwrap_or(rest.len());
        return Ok(rest[..end].trim());
    }
    if let Some(rest) = s.strip_prefix("```") {
        let end = rest.find("```").unwrap_or(rest.len());
        return Ok(rest[..end].trim());
    }
    Ok(s)
}
