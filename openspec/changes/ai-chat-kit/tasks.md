# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.
>
> Every Cucumber run uses `TEST_ENV_NUMBER=$RANDOM` and needs Redis on 6379. Every scenario carries a
> `# <ID> — <Happy path | Edge case | Error case>: …` comment naming its design.md worked example, and
> code comments name the IDs of the paths they implement.

## 1. Kit extraction — the Support Console renders through the kit, no visible change

- [x] 1.1 Create `AiChatHelper` by moving `SupportConsoleHelper`'s answer pipeline, follow-ups, title/when
      helpers and status badges, adding `mode: :strict / :rich`; leave `SupportConsoleHelper` as thin
      delegators (`mode: :strict`). LLD § Method Contracts (`AiChatHelper`), § File Map ④. Verify:
      `bundle exec rubocop app/packs/ai/ai_chat app/packs/ai/support_console` clean.
- [x] 1.2 Add `AiChatItem`, `AiChatRow`, `AiChatRows` (`Data.define`, grouped `MIN(id)` title
      query, `limit(51)` for "50+"). LLD § Method Contracts, § Queries and Indexes. Verify: in
      `bin/rails runner`, `AiChatRows.for_agent_sessions` on a dev session returns rows with titles in
      2 queries (check the log).
- [x] 1.3 Move the Console's partials into `app/packs/ai/ai_chat/views/ai_chat/` (`_layout`, `_sidebar`,
      `_conversation`, `_question`, `_answer`, `_pending`, `_empty_state`, `_composer` with
      captured slot locals) and make the Console's views render them with its own ids and slots
      (model, Stop, follow-ups, footer). LLD § File Map ③⑤①. Verify: the Console page in dev looks
      identical (compare against a screenshot taken before the change).
- [x] 1.4 Rename the Console's Stimulus controllers to `ai_chat_thread`, `ai_chat_composer`,
      `ai_chat_sidebar`; move the generic SCSS into `custom/ai_chat.scss` (`.ai-chat`), keeping
      Console-only rules in `support_console.scss`. LLD § File Map ⑥. Verify: no JS console errors
      on the Console page; the stylesheet compiles (`sassc` render).
- [x] 1.5 Update the Console's step definitions that assert `support-console-thread#…` /
      `support-console#…` data-action strings to the new names. Verify: `grep -rn "support-console-thread#\|support-console#fill" features` returns nothing.
- [x] 1.6 Write `features/ai_chat/answer_rendering.feature` for E8 (chart kept in `:rich`, stripped in
      `:strict`) and X6 (`<script>` / `on*=` stripped in `:rich`); run it with
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ai_chat/answer_rendering.feature`, then the
      Console suite (H1, X5) with `pcuc -n 4 features/support_console`, and confirm both are green
      before starting phase 2.

## 2. Assistants page on the kit

- [x] 2.1 `AssistantsController#show`: build rows (`AiChatRows.for_chats`, same scope as today's
      `@chats`, capped 50) and items; render `ai_chat/_layout` with frame `ai-chat-thread`
      (`turbo_action: advance`), header slot (owner link + Export menu) and empty state
      (`DESCRIPTION`, "Hello, <first name>"). LLD § Controllers. Verify: Fund I › Assistant in dev
      shows the sidebar and opening a row swaps only the thread.
- [x] 2.2 `#ask` / `#transcribe` respond with turbo_stream (append `_question` + `_pending` with id
      `assistant_response_<request_id>`); `AssistantQueryJob` broadcasts `ai_chat/_answer`
      (answered or failed) to replace it and drops `broadcast_hide_spinner`. LLD § Controllers,
      § Background Jobs, § Error Mapping. Verify: asking in dev shows "Thinking…" then the answer.
- [x] 2.3 Trim `voice_chat_controller.js` to recording/transcribing (posts via the kit form); move
      the mic + hint into the composer slot; delete `assistants/_ask` and `_ask_frame`. Verify: hold
      🎤 in dev, the transcribed question appears and is answered.
- [x] 2.4 Point `ppt_export_controller.js` and `slideshow_controller.js` at `[data-ai-chat-answer]` /
      `[data-ai-chat-answer-body]`; `_answer` emits both attributes. Verify: Export PowerPoint in dev
      produces a slide with an answer's table.
- [x] 2.5 Write `features/ai_chat/assistants_page.feature` for H2, H3, H4, E1, E3, E6, E7, E14, E16
      (Assistants), E17, X3 with `features/step_definitions/ai_chat_steps.rb`; run it with
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ai_chat/assistants_page.feature`, then the
      existing `features/ai/assistants` and `features/ai/fund_assistant` features, and confirm all are
      green before starting phase 3.

## 3. KPI analysis chat on the kit

- [x] 3.1 `ChatsController#show`: rows from `policy_scope(Chat)` with the same owner as `@chat`,
      items from `@chat.messages`; render `ai_chat/_layout` (`:rich`) with the document picker slot
      when the owner has PDF/CSV documents. Remove `faq_thread_controller` from `chats/show` only.
      LLD § Controllers. Verify: KPI report › Analysis › a chat in dev shows the kit page.
- [x] 3.2 `messages/_message` and `messages/_streamed_markdown` render `ai_chat/_question` /
      `_answer`, keeping `dom_id(message, "content")` as the chunk target. Verify: a streamed answer in
      dev grows in place with the blinking cursor and ends as a kit answer.
- [x] 3.3 Write `features/ai_chat/kpi_chat.feature` for H5, E5, E15, E16 (KPI), X4, X8; run it with
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ai_chat/kpi_chat.feature` and confirm it
      is green before starting phase 4.

## 4. Floating agent window on the kit (all agents, LP chat included)

- [x] 4.1 `GenericChatAgent.call` accepts `session_id:` (used only when agent, chattable, analyst and
      channel match) and `new_session:`; without them, today's rule. LLD § Method Contracts. Verify:
      `bin/rails runner` calls with and without the keywords create/continue sessions as described.
- [x] 4.2 `SupportAgentChatsController`: `index` → HTML thread, `sessions` → HTML rows
      (`AiChatRows.for_agent_sessions`), `create` → turbo_stream (question + answer, or a failed
      answer with the question returned), pass `session_id` / `new_session`, refuse a blank message;
      remove the JSON responses. LLD § Controllers, § Error Mapping. Verify: `grep -rn "agent_chat_controller\|chats/sessions" app/javascript` finds nothing after 4.3.
- [x] 4.3 Rewrite the body of `support_agents/_chat_panel` as the kit window (`variant: :window`):
      bubble, white header with Conversations / New / Maximise / Close, empty state with
      `sample_questions` as suggestion buttons, `_pending` template; add `ai_chat_window_controller`
      (toggle, drag, resize, maximise, Conversations view, `data-turbo-temporary` kept); delete
      `agent_chat_controller.js`. LLD § File Map ⑥①. Verify: on Acme Robotics and on Kavya's dashboard
      in dev, the window opens, asks, lists conversations, drags and maximises.
- [x] 4.4 Write `features/ai_chat/floating_window.feature` for H6, H7, H8, H11, H12, E2, E4, E9, E10,
      E11, E13, E16 (window), X1, X2, X7; run it with
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ai_chat/floating_window.feature`, then
      `features/ai/lp_assistant` and `features/ai/support_agents/portfolio_agent_run.feature`, and
      confirm all are green before starting phase 5.

## 5. Customer Support agent extras

- [x] 5.1 Add `ai_chat/_feedback` (👍/👎, note box after 👎, "Thanks for your feedback") rendered under
      answers only when the agent is `CustomerSupportAgent`, and `ai_chat_feedback_controller.js`
      calling the unchanged `feedback_support_agent_chat_path` PATCH. LLD § File Map ⑧. Verify: in
      dev, 👎 + note creates/updates the `AgentChatMessageFeedback` row.
- [x] 5.2 Map `AgentChatSession#status == "escalated"` to the Escalated badge (warning) in kit rows.
      Verify: an escalated dev session shows the badge under Conversations.
- [x] 5.3 Write `features/ai_chat/customer_support.feature` for H9, H10, E12, X9; run it with
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ai_chat/customer_support.feature`, then
      `features/customer_support_agent`, and confirm all are green before starting phase 6.

## 6. Docs and full regression

- [x] 6.1 Update the user guides that describe these screens — `ai_features_user_guide.md`,
      `support_agents_user_guide.md`, `customer_support_agent_user_guide.md` and the agent guides under
      `docs/user_guides/agents/` that mention the chat window — for the sidebar/Conversations list,
      suggestion Ask buttons and the unchanged 👍/👎; FAQs per the user-guide FAQ standard. Verify:
      `UserGuideLint` passes on the edited guides.
- [x] 6.2 Run every phase's feature plus the Console suite together with
      `pcuc -n 4 features/ai_chat features/support_console features/customer_support_agent features/ai/lp_assistant features/ai/assistants features/ai/fund_assistant`
      and confirm it is green; run `bundle exec rubocop` on all touched Ruby.
- [ ] 6.3 QA: run `qa-checklist.md` on a deployed build and record the sign-off (for QA, not the apply
      agent).

## 7. The answer layout (AI phase — added after phase 6 at the user's request)

- [x] 7.1 Extract the Console's layout and amounts rule into `AiChatAnswerLayout` and use it in
      `SupportConsoleClientBrief`, `BaseAssistant#run` (after each assistant's own prompt),
      `GenericChatAgent#setup_ruby_llm_chat` (web channel only — WhatsApp stays plain) and
      `ChatStreamJob` (`with_instructions(…, persist: false)`). Verify: H22, E19, E20.
- [x] 7.2 Questions-card Ask buttons on in both modes; follow-ups above the box on every screen through
      `AiChatHelper#ai_chat_follow_ups` + `ai_chat/_follow_ups` (the Console's rule, now shared; the
      Console uses it too). Verify: H19–H21.
- [x] 7.3 Floating window: Conversations and New as icon buttons; a Back to chat button in the list;
      opening a conversation or New from the list returns to the chat. Verify: browser smoke scenario.
- [x] 7.4 Write `features/ai_chat/answer_layout.feature` (H19–H22, E19, E20) and run it with the kit,
      Console, CS, LP and assistant features — 312/312.

## 8. Optional answer widgets (added at the user's request)

- [x] 8.1 `AiChatAnswerLayout::WIDGETS`: an optional catalogue (Verdict, Checks, What to do), each with the
      condition that calls for it and a "not for" line, plus three choosing examples (one with no widget).
      Verify: E53.
- [x] 8.2 `AiChatHelper` draws a well-formed widget (Verdict banner by opening word, Checks with failures
      first, What to do as numbered steps) and leaves a malformed one as plain text; a table's Status column
      gets badges for known status words. Verify: H23–H26, E51, E52.
- [x] 8.3 `AiChatAnswerLayout.log_usage` in every back end (Console, Assistants, record chat, agents on the
      web) logs which sections each answer used. Verify: E54.
- [x] 8.4 `rake ai_chat:widget_eval` — the shared prompt (ENTITY_ID=…) or a real assistant with its tools
      and data (ASSISTANT=… with its record and USER_ID=…, throwaway chat), questions per assistant in
      `config/ai_chat/widget_eval/`. Run by a developer against a real model (not in Cucumber).
- [x] 8.5 Write `features/ai_chat/widgets.feature` and run it with the kit, Console, CS, LP and assistant
      features — 326/326.

## 9. AI Slides redesign (added at the user's request)

- [x] 9.1 `SlideGeneratorService`: a new brief (5–8 slides, title → key figures → insights/chart → table or
      comparison → next steps; grounded numbers; the amounts rule; a takeaway per slide; an icon list) and
      `render_blueprint`, which normalises each slide (legacy names and saved blueprints without a
      `template` key, icon and tone allow-lists, empty slides dropped) without changing the blueprint.
      Verify: E55–E59, X48, X49.
- [x] 9.2 Templates `title, key_figures, insights, chart, table, comparison, next_steps` on one frame
      (`_frame`: icon, title, body, "What this means", footer record · date · n / total); filler text removed;
      styles in the presentation layout on its palette variables. Verify: H27.
- [x] 9.3 Saved decks are redrawn from their blueprint (no AI call); Regenerate makes a new one. Tabler
      icons load (the old CDN URL 404'd); `<meta charset>` so ₹ and × survive. AI Slides only for
      the user's own chat (found in review). Verify: H28, H29, X50.
- [x] 9.4 Widget eval follow-up: Checks gets the list/count/show exclusion Verdict already had (the
      model added Checks to a plain investment list), with a choosing example. "Why do TVPI and MOIC differ?"
      is an explanation, not a right-or-wrong question: the eval now expects no widget for it. Verify: E53.
- [x] 9.5 `rake ai_chat:widget_eval REPEAT=n` asks each question n times and reports how often each widget
      was used; a question passes when most of its answers are right (one sample could not tell "usually
      right" from "usually wrong").
