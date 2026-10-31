# AI Chat Kit — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/ai-chat-kit/spec.md) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document records the implementation-level decisions
> a reviewing developer must check. It adds to [design.md](design.md): link to its diagrams and
> worked examples rather than repeating them.

---

## Contents

- [Review Summary](#review-summary)
- [File Map](#file-map)
- [Schema Detail](#schema-detail)
- [Method Contracts](#method-contracts)
- [Controllers, Params and Responses](#controllers-params-and-responses)
- [Queries and Indexes](#queries-and-indexes)
- [Transactions, Locking and Concurrency](#transactions-locking-and-concurrency)
- [Background Jobs](#background-jobs)
- [External Integrations](#external-integrations)
- [Error Mapping and Logging](#error-mapping-and-logging)
- [Security Review](#security-review)
- [Configuration and Rollout](#configuration-and-rollout)
- [Test Plumbing](#test-plumbing)
- [Project Rules Checklist](#project-rules-checklist)
- [Sign-off](#sign-off)

---

## Review Summary

- **The window's JSON API is removed**, not kept beside the HTML — relies on `agent_chat_controller.js`
  being its only caller. See [Controllers](#controllers-params-and-responses).
- **`GenericChatAgent` gains `session_id:` / `new_session:`** (design decision 6, confirmed — resolves
  the design's open question on session choice). Defaults keep today's behaviour for WhatsApp. See [Method Contracts](#method-contracts).
- **Console helpers move to `AiChatHelper`** with `mode: :strict`; `SupportConsoleHelper` is removed
  (its views now call the kit helpers). See [File Map](#file-map).
- **Flat constant names** (`AiChatItem`, `AiChatRow`, `AiChatRows`): every directory under
  `app/packs` is an autoload root, so a nested `ai_chat/` namespace directory would define both
  `AiChat::Item` and `Item`.
- **Stimulus controllers are renamed** (`support_console_*` → `ai_chat_*`); the Console's step
  definitions that assert `data-action` strings change in the same phase.
- **Export/slides hook** moves from `.assistant-message-card` / `.prose` to `[data-ai-chat-answer]` /
  `[data-ai-chat-answer-body]`. See [File Map](#file-map).
- **Lists capped at 50** with grouped `MIN(id)` title queries — fixes today's N+1 in `sessions`.

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ② | `app/packs/ai/ai_chat/services/ai_chat_item.rb` | New | `AiChatItem` (`Data.define`) + `.from_message`, `.from_agent_chat_message` |
| ② | `app/packs/ai/ai_chat/services/ai_chat_row.rb` | New | `AiChatRow` (`Data.define`) |
| ② | `app/packs/ai/ai_chat/services/ai_chat_rows.rb` | New | `AiChatRows` (`rows`, `more`) + `.for_chats`, `.for_agent_sessions` (grouped title query, cap 50) |
| ③ | `app/packs/ai/ai_chat/views/ai_chat/_layout.html.erb` | New | Panes; `variant: :page` / `:window` |
| ③ | `app/packs/ai/ai_chat/views/ai_chat/_sidebar.html.erb`, `_conversation.html.erb` | New (moved from `support_console/show`, `_conversation`) | List, search, groups, footer |
| ③ | `app/packs/ai/ai_chat/views/ai_chat/_thread.html.erb` | New (from `support_console/_chat`) | Thread pane (header/streams/empty/below/composer slots) |
| ③ | `app/packs/ai/ai_chat/views/ai_chat/_question.html.erb`, `_answer.html.erb`, `_pending.html.erb`, `_empty_state.html.erb`, `_suggestions.html.erb` | New (moved from `support_console/_message`, `_composer`) | Thread items, suggestion buttons |
| ④ | `app/packs/ai/ai_chat/helpers/ai_chat_helper.rb` | New (moved from `SupportConsoleHelper`) | `ai_answer_html`, `ai_follow_ups`, `ai_chat_title`, `ai_chat_when`, `ai_chat_group`, `AI_CHAT_STATUS_BADGES` |
| ④ | `app/packs/ai/support_console/helpers/support_console_helper.rb` | Deleted (moved to `AiChatHelper`) | — |
| ④ | `config/application.rb` | Modified | `ai_chat` added to the AI packs' view/helper paths |
| ⑤ | `app/packs/ai/ai_chat/views/ai_chat/_composer.html.erb` | New (moved from `support_console/_composer`) | Box + captured slot locals |
| ⑤ | `app/packs/ai/support_console/views/support_console/_composer.html.erb` | Modified | Fills slots (model, Stop, follow-ups, footer) |
| ⑥ | `app/javascript/controllers/ai_chat_thread_controller.js` | New (renamed `support_console_thread_controller.js`) | As design ⑥ |
| ⑥ | `app/javascript/controllers/ai_chat_composer_controller.js` | New (renamed `support_console_controller.js`) | + `_pending` template insertion |
| ⑥ | `app/javascript/controllers/ai_chat_sidebar_controller.js` | New (renamed `support_console_sidebar_controller.js`) | As design ⑥ |
| ⑥ | `app/javascript/controllers/ai_chat_window_controller.js` | New (window parts of `agent_chat_controller.js`) | Toggle, drag, resize, maximise, Conversations view |
| ⑥ | `app/javascript/controllers/agent_chat_controller.js` | Deleted | Replaced by ⑥ + ⑧ |
| ⑥ | `app/javascript/controllers/voice_chat_controller.js` | Modified | Recording/transcribe only; posts via the kit form |
| ⑥ | `app/javascript/controllers/ppt_export_controller.js`, `slideshow_controller.js` | Modified | Read `[data-ai-chat-answer]` / `[data-ai-chat-answer-body]` |
| ⑥ | `app/assets/stylesheets/custom/ai_chat.scss` | New (generic parts of `support_console.scss`) | `.ai-chat` styles |
| ⑥ | `app/assets/stylesheets/custom/support_console.scss` | Modified | Console-only rules (machine badge, fit) |
| ① | `app/packs/ai/assistants/views/assistants/show.html.erb` | Modified | Renders `ai_chat/_layout` |
| ① | `app/packs/ai/assistants/views/assistants/_ask.html.erb`, `_ask_frame.html.erb` | Deleted | Replaced by ③ |
| ① | `app/packs/ai/chats/views/chats/show.html.erb` | Modified | Renders `ai_chat/_layout` |
| ① | `app/packs/ai/chats/views/messages/_message.html.erb`, `_streamed_markdown.html.erb` | Modified | Render ③ (keep `dom_id(message, "content")`) |
| ① | `app/packs/ai/support_agents/views/support_agents/_chat_panel.html.erb` | Modified (body rewritten) | Kit window; hosts unchanged |
| ① | `app/packs/ai/support_console/views/support_console/show.html.erb`, `_chat.html.erb`, `_message.html.erb`, `_conversation.html.erb` | Modified | Render ③ with Console ids |
| ⑦ | `app/packs/ai/assistants/controllers/assistants_controller.rb` | Modified | `ask`/`transcribe` → turbo_stream; rows/items for `show` |
| ⑦ | `app/packs/ai/assistants/jobs/assistant_query_job.rb` | Modified | Broadcast `ai_chat/_answer`; drop `broadcast_hide_spinner` |
| ⑦ | `app/packs/ai/chats/controllers/chats_controller.rb` | Modified | `show` builds rows/items |
| ⑦ | `app/packs/ai/support_agents/controllers/support_agent_chats_controller.rb` | Modified | HTML/turbo_stream; session params |
| ⑦ | `app/packs/ai/support_agents/services/generic_chat_agent.rb` | Modified | `session_id:` / `new_session:` |
| ⑧ | `app/packs/ai/ai_chat/views/ai_chat/_feedback.html.erb` | New | 👍/👎 + note |
| ⑧ | `app/javascript/controllers/ai_chat_feedback_controller.js` | New (from `agent_chat_controller#rateFeedback/submitFeedbackNote`) | PATCH feedback |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/ai/ai_chat/{services,helpers,views}`)
- [ ] No host view of `_chat_panel` (9 files) is edited
- [ ] `faq_thread_controller.js` is kept (FAQ threads still use it)

---

## Schema Detail

N/A — no tables or columns change.

**Reviewer checks**
- [ ] `db/schema.rb` and `db/schema_test.rb` are not modified

---

## Method Contracts

**`AiChatItem`** (value)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.from_message(m)` | `Message` | `Item` (`status: :pending` if assistant + blank content, else `:answered`) | — | none | Yes |
| `.from_agent_chat_message(m)` | `AgentChatMessage` (feedback preloaded) | `Item` (`status` from `metadata["turn_status"]` → `:pending`/`:failed`/`:stopped`/`:refused`/`:answered`) | — | none | Yes |

**`AiChatRows`** (service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.for_chats(scope, url:)` | `Chat` relation (already scoped), `url:` proc `(chat) -> String` | `Array<Row>` ≤ 50, newest first | — | 2 queries | Yes |
| `.for_agent_sessions(scope, url:)` | `AgentChatSession` relation (already scoped) | `Array<Row>` ≤ 50; `status: "escalated"` kept | — | 2 queries | Yes |

**`AiChatHelper`** (helper)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `ai_answer_html(text, mode:)` | `String`, `:strict`/`:rich` | `SafeBuffer` | `ArgumentError` on unknown mode | none | Yes |
| `ai_follow_ups(text)` | `String` | `Array<String>` ≤ 3 | — | none | Yes |
| `ai_chat_title(question)` | `String, nil` | `String` (quotes trimmed, "New conversation") | — | none | Yes |
| `ai_chat_when(time)` | `TimeWithZone` | `l(time, format: :time_only)` today, else `l(date)` | — | none | Yes |

**`GenericChatAgent`** (service, modified)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(support_agent_id:, target:, user_message:, analyst_id:, session_id: nil, new_session: false, channel: …)` | as today + two optional | as today | as today | as today; `new_session: true` creates a session; `session_id` used only if `support_agent`, `chattable`, `analyst_id`, `channel` all match, else today's rule | No (writes messages) — the composer blocks double submit |

**Reviewer checks**
- [ ] Every raised error is handled by a caller or listed in Error Mapping
- [ ] `session_id` is matched on agent + chattable + analyst + channel (never id alone)
- [ ] Callers that pass neither keyword (WhatsApp) behave exactly as before

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `AssistantsController#show` | `assistant_type`, `chat_id`, `new`, `owner_id`, `owner_type` (unchanged) | `:assistant, :show?` | HTML `ai_chat/_layout` (frame `ai-chat-thread`, `turbo_action: advance`) | As today |
| `AssistantsController#ask` | `query`, `assistant_type`, `chat_id` (unchanged) | as today | turbo_stream: append `_question` + `_pending` (id `assistant_response_<request_id>`) | turbo_stream: failed `_answer` |
| `AssistantsController#transcribe` | `audio`, `chat_id`, `assistant_type` | `:assistant, :transcribe?` | same as `ask` | failed `_answer` |
| `ChatsController#show` | unchanged | `ChatPolicy#show?` | HTML `ai_chat/_layout` | As today |
| `SupportAgentChatsController#index` | `chattable_type`, `chattable_id`, `session_id` | `SupportAgent#show?` | HTML: thread of the session (frame `ai-chat-thread`) | 404 for another user's session id (find_by scoped → empty thread) |
| `SupportAgentChatsController#sessions` | `chattable_type`, `chattable_id` | `SupportAgent#show?` | HTML: `ai_chat/_sidebar` rows | — |
| `SupportAgentChatsController#create` | `message`, `chattable_type`, `chattable_id`, `session_id`, `new_session` | `SupportAgent#show?` | turbo_stream: replace `_pending` with `_question` + `_answer` (+ `_feedback` for CS); update sidebar row | turbo_stream: failed `_answer` (503 connectivity / 422 failure / 500 other), question text returned to the box |
| `SupportAgentChatsController#destroy` | `id` | `SupportAgent#show?` | turbo_stream remove row | As today |
| `SupportAgentChatFeedbacksController#update` | unchanged | unchanged | JSON (unchanged) | unchanged |

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`
- [ ] Permitted params can't set `entity_id`, `user_id`, `analyst_id` or `support_agent_id`
- [ ] Blank `message` is refused before `GenericChatAgent` is called (E4)
- [ ] `new_session` is cast with `ActiveModel::Type::Boolean`

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `AiChatRows.for_chats` | `scope.order(updated_at: :desc).limit(51)` then `Message.where(chat_id:, role: "user").group(:chat_id).minimum(:id)` + `pluck(:chat_id, :content)` | `messages.chat_id` | ≤ 51 / ≤ 50 | `includes(:user)` |
| `AiChatRows.for_agent_sessions` | `scope.order(updated_at: :desc).limit(51)` + `AgentChatMessage.where(agent_chat_session_id:, role: "user").group(...).minimum(:id)` + `pluck` | `agent_chat_messages.agent_chat_session_id` | ≤ 51 | `includes(:analyst)` |
| Assistants rows scope | `Chat.where(user:, entity_id:, assistant_type:)` (+ owner when present) | `chats.user_id` | small | — |
| Window thread | `session.agent_chat_messages.includes(:feedback).order(:created_at)` | FK | one conversation | `includes(:feedback)` |

`limit(51)` decides "50+": show 50, footer "50+ conversations" when 51 came back.

**Reviewer checks**
- [ ] Every query is scoped by `entity_id` / `analyst_id` / `user_id` as today
- [ ] No N+1 on list pages (titles are 2 queries per list, not one per row)
- [ ] `.distinct` queries, if any, call `unscope(:order)` first (MySQL)

---

## Transactions, Locking and Concurrency

N/A — no new multi-row writes; message writes stay inside the existing agents/jobs.

**Reviewer checks**
- [ ] The composer blocks a second submit while one is pending (window and Assistants)

---

## Background Jobs

| Job | Queue | Trigger | Retry / backoff | Discard on | Concurrency guard | Timeout |
|---|---|---|---|---|---|---|
| `AssistantQueryJob` (modified render only) | `:default` | `ask` / `transcribe` | as today | as today | none (as today) | `TIMEOUT = 180.seconds` (unchanged) |
| `ChatStreamJob` (unchanged; renders via `Message` broadcasts) | `:default` | `send_message` | as today | as today | — | — |

**Reviewer checks**
- [ ] A broadcast for an answer whose pending element is gone (user left) is harmless

---

## External Integrations

N/A — no new third-party calls; LLM calls are unchanged.

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| Connectivity (`SocketError`, timeouts…) | `GenericChatAgent` | `SupportAgentChatsController#create` (existing matcher) | Failed answer: "AI service is temporarily unreachable (network/DNS). Please try again shortly." | `warn` (as today) |
| Result failure | `GenericChatAgent` | `create` | Failed answer: "Chat agent execution failed" | as today |
| Other `StandardError` | `create` | `create` | Failed answer: "Chat error: <message>" (as today) | `error` + 5 backtrace lines (as today) |
| `Timeout::Error` | `AssistantQueryJob` | job | Failed answer: "The request timed out. Please try again or refine your query." | as today |
| `StandardError` | `AssistantQueryJob` | job | Failed answer with the message (as today) | as today |
| `StandardError` | `ChatStreamJob` | job | In-app alert (as today) | as today |
| Unknown `mode` | `ai_answer_html` | none (programming error) | 500 in dev/test | exception tracker |

**Reviewer checks**
- [ ] No bare `rescue => e` that swallows errors silently
- [ ] Every failed answer leaves the question text back in the box

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | Unchanged per action (table above); window session reads/writes scoped by `analyst_id: current_user.id` |
| Tenant isolation | Assistants: `entity_id: current_user.entity_id`; Chats: `policy_scope(Chat)`; window: agent policy + analyst; LP chat: `chattable: current_user` |
| Secrets | None handled |
| Input / output sanitisation | `:strict` = Console allow-list (X24); `:rich` = `markdown_to_html` allow-list; kit adds only fixed classes/attributes; `data-prompt` / `aria-label` values ERB/Nokogiri-escaped |
| Mass assignment | No model mass-assignment added; `session_id` / `new_session` read individually |
| Existing (unchanged) | `find_chattable` constantizes `chattable_type` — recorded as a follow-up in design Risks |

**Reviewer checks**
- [ ] A user from another entity cannot reach any record through any route, job or MCP tool
- [ ] An investor's `session_id` for another investor's conversation is ignored (X7)
- [ ] `:rich` output contains no `<script>` or `on*=` attributes (X6)

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None |
| Feature flag | None — each phase ships whole (design FAQ) |
| Cron / schedules | None |
| Deploy order | Code only; assets precompile (new SCSS/JS) |
| Rollback | Revert the deploy; no data to clean up |

**Reviewer checks**
- [ ] Safe to deploy with the feature unused, and safe to roll back
- [ ] `config/importmap.rb` / controller index picks up the renamed controllers (eager-loaded)

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/ai_chat/answer_rendering.feature` | — | — | `When the answer {string} is rendered in {word} mode` |
| `features/ai_chat/assistants_page.feature` | assistant `#run` stubbed; job inline; `RubyLLM.transcribe` stubbed | `:fund`, `:chat`, `:message` | `Given {string} has Fund Assistant chats …`, `Then the sidebar lists …` |
| `features/ai_chat/kpi_chat.feature` | `Chat#ask` stubbed to yield chunks | `:kpi_report`, `:chat`, `:document` | `Given the KPI report {string} has a chat …` |
| `features/ai_chat/floating_window.feature` | `GenericChatAgent.call` stubbed (success / failure / raise) | `:support_agent`, `AgentChatSession` | `When I open the chat window on {string}`, `When I ask in the window {string}` |
| `features/ai_chat/customer_support.feature` | as above | CS agent, `AgentChatMessageFeedback` | `When I rate the answer {word} with note {string}` (PATCH) |
| `features/support_console/*.feature` | existing | existing | Update steps asserting `support-console-thread#…` → `ai-chat-thread#…` |

All share `features/step_definitions/ai_chat_steps.rb`; rack_test like the Console's features.

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | Rows/items take arrays; scopes tested with `exists?` |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | N/A | No dedup or bulk ops |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | N/A | No `account_entries`; only `includes(:user/:analyst/:feedback)` |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` via `EmailDateLocalization`; no human-format `strftime` | Applies | `ai_chat_when` uses `l(...)`; no emails |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | N/A | No date inputs; no JS-rendered dates |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | Unchanged policies; see Security Review |
| MCP tool surfaces changed only via the ontology YAML (run the ontology drift feature) | N/A | No MCP change |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | Test Plumbing |
| `bundle exec rubocop` clean, including the `IRM/RelationBlankPresent` cop | Applies | Run per phase |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
