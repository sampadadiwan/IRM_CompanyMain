# WhatsApp AI Agent Integration — Technical Design

## 1. Overview

Route inbound WhatsApp messages (via the WATI webhook) through a dispatcher that identifies the user, resolves the correct AI agent (LP Assistant or Customer Support Agent), invokes `GenericChatAgent`, formats the response for WhatsApp, and sends it back via the WATI API.

**Goal**: One dispatcher service, minimal modifications to existing code, identical agent behaviour across web and WhatsApp channels.

---

## 2. Architecture

### 2.1 Webhook Ingestion

```
WATI Webhook POST /users/whatsapp_webhook
  → UsersController#whatsapp_webhook
  → WhatsappAgentJob.perform_later(params.to_json)   ← returns 200 immediately
  → WhatsappAgentJob#perform(params_json)
      ├── Parse JSON
      ├── Filter: eventType == "message" AND owner == false (inbound only)
      ├── Lookup user by waId (phone number)
      ├── Check enable_whatsapp permission on entity
      └── WhatsappChatDispatcher.call(user_id:, message_text:, conversation_id:)
```

**Webhook events handled**: only `eventType: "message"` with `owner: false` (inbound user messages).

**Webhook events ignored**: `sessionMessageSent`, `templateMessageSent`, `templateMessageFailed`, and any event with `owner: true`.

**Key webhook fields used**:

| Field            | Usage                                                  |
|------------------|--------------------------------------------------------|
| `eventType`      | Must be `"message"` to proceed                         |
| `owner`          | Must be `false` (inbound from user)                    |
| `waId`           | Sender's phone number — used to look up the User record |
| `text`           | Message content passed to the dispatcher               |
| `conversationId` | WATI conversation ID — passed through for reply targeting |

### 2.2 Dispatcher Flow

```
WhatsappChatDispatcher.call(user_id:, message_text:, conversation_id:)
  ├── find_or_create_wa_session
  │     ├── Find active session (updated within 30 min) → return existing
  │     └── Create new skeleton session with placeholder agent
  └── Route by wa_state:
        nil                     → handle_new_session
        awaiting_agent_selection → handle_agent_selection
        awaiting_fund_selection  → handle_fund_selection
        active                   → handle_active_session
```

### 2.3 State Machine

```
nil
 │  auto-select (1 agent)           ┌─ auto-select LP → awaiting_fund_selection
 │  or present menu (2+ agents) ────┤
 ▼                                  └─ auto-select CS → active
awaiting_agent_selection
 │  user picks agent
 ▼
 ├─ LP Assistant → awaiting_fund_selection
 │                    │  user picks fund (or auto-select if 1 fund)
 │                    ▼
 └─ CS Agent ──────► active
                       │  normal conversation loop
                       │  "menu" → reset to nil
                       │  "thanks"/"bye"/"done" → feedback prompt → session ends
                       ▼
                     (session expires after 30 min inactivity)
```

### 2.4 Key Design Principle

The dispatcher handles **channel-specific concerns** (menus, fund selection, feedback, response formatting). The agent layer (`GenericChatAgent`, providers, tools) remains **channel-agnostic**.

---

## 3. Components

### 3.1 WhatsappAgentJob

**File**: `app/packs/ai/support_agents/jobs/whatsapp_agent_job.rb`

- Receives the full webhook params JSON from the controller
- Parses and validates: filters to `eventType == "message"` and `owner == false`
- Looks up user by `waId`: last 10 digits as `phone`, remainder as `call_code`
- Checks `enable_whatsapp` permission via entity chain
- Enqueues with `retry: 2`

### 3.2 WhatsappChatDispatcher

**File**: `app/packs/ai/support_agents/services/whatsapp_chat_dispatcher.rb`

**Constructor params**:

| Param             | Type    | Description                                      |
|-------------------|---------|--------------------------------------------------|
| `user_id`         | Integer | DB id of the user                                |
| `message_text`    | String  | Stripped inbound message text                    |
| `conversation_id` | String  | WATI conversation ID from webhook (optional)     |

**Agent eligibility**:

| Agent type           | Accessible by                                                          |
|----------------------|------------------------------------------------------------------------|
| `LpAssistantAgent`   | Users with an approved `InvestorAccess` record for the agent's entity  |
| `CustomerSupportAgent` | All users (no additional access check)                               |

**Session**: stored in `AgentChatSession` with `channel: "whatsapp"`, `status: "active"`, and state tracked in `wa_state` / `wa_metadata`.

**Session timeout**: 30 minutes of inactivity. Next message creates a new session.

**Keywords**:

| Keyword         | Regex                          | Effect                          |
|-----------------|--------------------------------|---------------------------------|
| `menu`          | `/\A\s*(menu)\s*\z/i`         | Resets session, shows menu again |
| `thanks/bye/done` | `/\b(thanks\|bye\|done)\b/i` | Ends conversation, triggers feedback prompt (CS Agent only) |

**send_message**: passes `conversation_id` and `whatsapp_number` to `WhatsappGeneralNotification.send_session_message`. Entity settings (endpoint, token) resolved from the agent's entity, falling back to the user's entity.

### 3.3 WhatsappGeneralNotification

**File**: `app/packs/core/users/jobs/whatsapp_general_notification.rb`

Two endpoint constants:

| Constant               | Credential key           | Used for             |
|------------------------|--------------------------|----------------------|
| `WHATSAPP_V1_ENDPOINT` | `WHATSAPP_API_ENDPOINT`  | v1 API methods       |
| `WHATSAPP_V3_ENDPOINT` | `WATI_V3_ENDPOINT`       | v3 ext API methods   |

**Note**: v1 endpoint includes the account ID path (e.g. `https://live-mt-server.wati.io/104710`). v3 endpoint is the bare host (e.g. `https://live-mt-server.wati.io`) — the v3 ext API does not include the account ID in the URL path.

**Methods**:

| Method                     | API endpoint                                         | Auth         | Notes                                              |
|----------------------------|------------------------------------------------------|--------------|----------------------------------------------------|
| `send_message`             | `POST /api/v1/sendTemplateMessage`                   | Raw token    | Legacy v1 template; used from `perform`            |
| `send_template_message`    | `POST /api/ext/v3/messageTemplates/send`             | Bearer token | v3; `custom_params: [{name:, value:}]` per recipient |
| `send_session_message`     | `POST /api/v1/sendSessionMessage/{phone}?messageText=` | Raw token  | v1; used by dispatcher; URL-encoded message        |
| `send_session_message_new` | `POST /api/ext/v3/conversations/messages/text`       | Bearer token | v3; `target` = `conversation_id`                   |
| `send_session_document`    | `POST /api/v1/sendSessionFile/{phone}?caption=`      | Raw token    | v1; base64-encoded file; URL-encoded caption       |
| `send_session_document_new`| `POST /api/ext/v3/conversations/messages/file`       | Bearer token | v3; binary multipart; `target` = `conversation_id` |
| `send_file_via_url`        | `POST /api/ext/v3/conversations/messages/fileViaUrl` | Bearer token | v3; JSON body `{target, file_url, caption?}`       |

**Auth token format**: The stored token (`WHATSAPP_ACCESS_TOKEN`) is a JWT that already includes the `Bearer ` prefix. v1 methods use it as-is; v3 methods also use it as-is (no additional `"Bearer "` prepended).

**`send_template_message` body shape**:

```json
{
  "template_name": "code_verification",
  "broadcast_name": "General Notification Broadcast",
  "recipients": [
    {
      "phone_number": "917721046692",
      "custom_params": [
        { "name": "1", "value": "112233" }
      ]
    }
  ]
}
```

`name` in `custom_params` must match the variable name defined in the WATI template (e.g. `"1"` for `{{1}}`).

---

## 4. Data Model

No new tables. Existing tables used with `channel: "whatsapp"`:

| Table                | Relevant fields                                                         |
|----------------------|-------------------------------------------------------------------------|
| `agent_chat_sessions`| `channel`, `wa_state`, `wa_metadata` (JSON), `analyst_id`, `status`    |
| `agent_chat_messages`| `channel`, `role` (user/assistant)                                      |
| `agent_message_feedbacks` | `channel`, `rating`, `notes`                                       |

**`wa_state` values**:

| Value                      | Meaning                                  |
|----------------------------|------------------------------------------|
| `nil`                      | Brand new session, no interaction yet    |
| `"awaiting_agent_selection"` | Menu sent, waiting for user's number   |
| `"awaiting_fund_selection"` | Fund menu sent, waiting for user's number |
| `"active"`                 | Agent and fund (if LP) resolved, open conversation |

**`wa_metadata` keys**:

| Key                    | Type    | Meaning                                             |
|------------------------|---------|-----------------------------------------------------|
| `agent_options`        | Hash    | `{"1" => {agent_type:, support_agent_id:, label:}}` |
| `fund_options`         | Hash    | `{"1" => {fund_id:, fund_name:}}`                   |
| `selected_fund_id`     | Integer | Fund chosen by the user                             |
| `awaiting_feedback`    | Boolean | Feedback prompt was sent                            |
| `awaiting_feedback_notes` | Boolean | Waiting for negative feedback detail             |

---

## 5. Configuration

### 5.1 Credentials / Environment

| Key                    | Where set       | Used for                                      |
|------------------------|-----------------|-----------------------------------------------|
| `WHATSAPP_API_ENDPOINT`| Rails credentials| v1 endpoint (includes account ID path)        |
| `WATI_V3_ENDPOINT`     | Rails credentials| v3 ext API base URL (bare host, no path)      |
| `WHATSAPP_ACCESS_TOKEN`| Rails credentials| Auth token (JWT with `Bearer ` prefix already)|
| `CAPHIVE_NOTIFICATION` | ENV             | v1 template name for general notifications    |

Per-entity overrides: `EntitySetting#whatsapp_endpoint`, `EntitySetting#whatsapp_token` — when set, these take precedence over global credentials.

### 5.2 Entity Permissions

The `enable_whatsapp` permission must be set on the entity (or its investor entities) for the job to proceed.

---

## 6. Error Handling

| Scenario                                 | Behaviour                                                        |
|------------------------------------------|------------------------------------------------------------------|
| Unknown `waId`                           | Job logs and returns — no message sent                           |
| `enable_whatsapp` not set                | Job returns silently                                             |
| `@user` not found in dispatcher          | Logs warning, no message sent (can't identify WATI endpoint)     |
| No eligible agents for user              | Sends "no AI assistants available" message, returns nil session  |
| `@entity_setting` nil                    | Logs error in `send_message`, returns without sending            |
| Non-JSON WATI response                   | `parse_response` logs HTTP code + body, returns error hash       |
| `StandardError` in `call`                | Rescue logs `user_id`, class, message, and first 5 backtrace lines |

---

## 7. Testing

```bash
bundle exec rspec spec/services/whatsapp_chat_dispatcher_spec.rb
bundle exec rspec spec/jobs/whatsapp_agent_job_spec.rb
bundle exec cucumber features/ai/support_agents/whatsapp_ai_agent.feature
```

**Manual webhook test** (Rails console):

```ruby
# Simulate inbound message
WhatsappAgentJob.new.perform({
  "eventType" => "message",
  "owner" => false,
  "waId" => "917721046692",
  "text" => "hello",
  "conversationId" => "642aa45abf5ae9401489c69c"
}.to_json)
```

**Test template message**:

```ruby
WhatsappGeneralNotification.send_template_message(
  { recipients: [{ phone_number: "917721046692", custom_params: [{ name: "1", value: "112233" }] }] },
  template_name: "code_verification"
)
```

---

## 8. Deployment Checklist

- [ ] Add `WATI_V3_ENDPOINT` to Rails credentials (bare host, no path)
- [ ] Run test suite and Cucumber features
- [ ] Manual end-to-end test with staging WATI webhook
- [ ] Monitor Sidekiq logs for `WhatsappAgentJob` errors post-deploy
- [ ] Verify `EntitySetting#fetch_whatsapp_endpoint` / `fetch_whatsapp_token` per entity
- [ ] Deprecate legacy `WhatsappChatJob` after 1-2 weeks stable
