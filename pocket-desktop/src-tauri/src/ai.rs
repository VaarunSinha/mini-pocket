//! AI processing for notes: todo list, summary, reminders via OpenAI API (gpt-4o).
//! API key is loaded from OPENAI_API_KEY env var.

use serde::{Deserialize, Serialize};

const OPENAI_API_URL: &str = "https://api.openai.com/v1/chat/completions";
const MODEL: &str = "gpt-4o";
const ENV_OPENAI_API_KEY: &str = "OPENAI_API_KEY";

/// System prompt describing the required JSON shape for ProcessedNoteFields.
const SYSTEM_PROMPT: &str = r#"You extract structured data from notes. Respond with a single JSON object only, no markdown or explanation, with these exact keys:

- "todo_list": array of strings. Each string MUST use this exact format: "[Priority] Assignee: task description"
  * Priority: one of [High], [Medium], [Low]. Use [High] for urgent, ASAP, critical, or time-sensitive tasks; [Low] for "when you get a chance", "no rush", or optional items; [Medium] otherwise.
  * Assignee: "Myself" if the note-taker does it (e.g. "I need to...", "I have to..."); or the person's name if someone else (e.g. "Arjun do this" → "Arjun").
  * Example: "[High] Myself: Submit proposal by Friday", "[Medium] Arjun: Send the report", "[Low] Myself: Review when free".
  Empty array if no actionable todos.

- "summary": string (one short paragraph).

- "reminders": array of strings. Each string MUST use: "[Priority] Assignee: date/time/event". Same priority and assignee rules as todo_list. Example: "[High] Myself: Submit by 24 March", "[Medium] Arjun: Meeting Friday". Empty array only if the note has no dates or commitments. Never leave reminders empty when the note mentions any future date, deadline, or meeting."#;

const USER_PROMPT_PREFIX: &str = r#"Extract from this note (voice memo or text): todo_list, summary, and reminders.
CRITICAL: Each todo and reminder must start with [High], [Medium], or [Low], then assignee (Myself or name), then ": ", then the content. Example: "[High] Myself: Get back by tomorrow". Do not put other people's tasks under Myself.

Note:
---
"#;
const USER_PROMPT_SUFFIX: &str = "\n---";

/// Result of AI processing for one note.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProcessedNoteFields {
    #[serde(rename = "todo_list")]
    pub todo_list: Vec<String>,
    pub summary: String,
    pub reminders: Vec<String>,
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

/// Process note content with OpenAI gpt-4o; returns todo_list, summary, reminders.
/// Requires OPENAI_API_KEY to be set in the environment.
pub async fn process_note_with_ai(
    state: tauri::State<'_, AiModelState>,
    note_content: String,
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
    let user_content = format!("{}{}{}", USER_PROMPT_PREFIX, content, USER_PROMPT_SUFFIX);

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

    Ok(ProcessedNoteFields {
        todo_list: parsed
            .todo_list
            .into_iter()
            .filter(|s| !s.is_empty())
            .collect(),
        summary: parsed.summary.trim().to_string(),
        reminders: parsed
            .reminders
            .into_iter()
            .filter(|s| !s.is_empty())
            .collect(),
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
