# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> **Implementation detail:** files, method contracts, schema detail and config for every task are
> in [lld.md](lld.md). Phase 1 → File Map, Schema Detail, External Integrations, Security Review.
> Phase 2 → Method Contracts, Queries and Indexes, Transactions, Background Jobs. Phase 3 →
> Controllers, Params and Responses. Phase 4 → Error Mapping and Logging, Configuration and Rollout.

> **Migrations:** the local dev DB lags `schema.rb`. After each `db:migrate`, restore
> `db/schema.rb` / `db/schema_test.rb`, hand-insert only this change's additions, and run
> `db:clean_schema`.

## 1. Granola connections (connect, verify, disconnect)

- [ ] 1.1 Add migration `create_granola_connections` per design.md (unique `[entity_id, scope_key]`); migrate and verify `granola_connections` appears in `db/schema.rb` and `db/schema_test.rb` with only the intended columns
- [ ] 1.2 Create `app/packs/core/granola/models/granola_connection.rb` (`encrypts :api_key`, kinds/statuses, `scope_key` callback, `api_key_last4`, `syncable` scope); verify in `rails runner` that a saved key reads back decrypted and the raw DB column is ciphertext, and that a second `kind: "user"` row for the same user raises `RecordNotUnique`
- [ ] 1.3 Create `app/packs/core/granola/services/granola_client.rb` (Faraday; `list_notes`, `get_note`, `verify!`; `AuthError` / `RetryableError` / `Error`; 0.2s throttle; `Retry-After` on 429); verify with `rails runner` against a stubbed Faraday adapter that 401 → `AuthError` and 503 → `RetryableError`
- [ ] 1.4 Create `granola_connection_policy.rb` per design.md Policy; verify in `rails runner` that a non-admin employee gets `create?` false for `kind: "workspace"` and true for their own `kind: "user"`
- [ ] 1.5 Create `granola_connections_controller.rb` (`create` with `verify!`, `update` reconnect, `destroy`, `sync`) and routes in `config/routes/core.rb`; verify `bin/rails routes | grep granola_connections` lists the four routes
- [ ] 1.6 Create `_granola_connection.html.erb` (connected / needs-attention / not-connected states, masked key, visibility warning, `data-turbo-confirm` on Disconnect) and render it on `users/show.html.erb` (own profile) and `entities/_form_fields.html.erb` (workspace, policy-gated); verify both pages render in dev with and without a connection
- [ ] 1.7 Create `docs/user_guides/granola_notes_sync_user_guide.md` with the "Connecting Granola" section and FAQs (`**Q?**` + answer on the next line, answers verified from code); verify with `UserGuideLint`
- [ ] 1.8 Add `features/support/granola_api_stub.rb` (WebMock stubs for `/v1/notes` and `/v1/notes/:id` from fixtures), `features/step_definitions/granola_steps.rb`, and `spec/factories/granola_connections.rb`, then write `features/core/granola/granola_connections.feature` (`@sync-http`) covering worked examples H1, E11, X1, X2, X3. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/granola/granola_connections.feature` and confirm it passes before starting phase 2

## 2. Sync, matching and auto-filing

- [ ] 2.1 Add migrations `create_granola_meetings` and `add_granola_to_notes` per design.md; migrate and verify both tables/columns in `db/schema.rb` and `db/schema_test.rb`
- [ ] 2.2 Create `granola_meeting.rb` (statuses, scopes, `upsert_from_api!` with author resolution and the private-notes-only-from-user-connections rule, `mark_needs_review!`, `mark_ignored!` which nils summary/private notes, `resolve!`); verify in `rails runner` that upserting the same payload twice yields one row and a workspace upsert does not blank existing private notes
- [ ] 2.3 Create `granola_attendee_matcher.rb` (internal-user exclusion, exact contact match grouped by investor, domain fallback excluding `PUBLIC_EMAIL_DOMAINS`, tiers `exact/domain/none/internal`); verify in `rails runner` against dev data that a known contact email returns `:exact` with that investor and a `@gmail.com` stranger returns `:none`
- [ ] 2.4 Create `granola_note_filer.rb` `call` (entity-scoped investor load, skip `filed_investor_ids`, Redcarpet with `escape_html: true`, `Note.create!` with touch point + `granola` tag + `granola_meeting`, digest after save, transaction + `meeting.lock!`); verify in `rails runner` that filing creates one note per investor and a second call creates none
- [ ] 2.5 Update `Note`: `belongs_to :granola_meeting`, `granola_detached?`, and the `update_investor` Granola branch (`max(current, on)`; manual notes unchanged); verify in `rails runner` that a manual note still sets `last_interaction_date` from `created_at`
- [ ] 2.6 Update `notes/_note.html.erb` (Open in Granola link, detached line) and add `:granola_meeting` to `NotesController` preloads; verify the investor Notes tab renders a Granola note with the link and no extra per-row queries in the dev log
- [ ] 2.7 Create `granola_meeting_processor.rb` and `granola_sync_service.rb` (claim, paginate, per-page existing-meeting lookup, skip unchanged/discarded, per-meeting rescue that holds the cursor, `record_success!`) plus `GranolaConnection#claim_sync!` / `#record_success!`; verify with `rails runner` against the stub fixtures that one pass files, parks and ignores as expected and advances `cursor_at`
- [ ] 2.8 Create `granola_sync_job.rb` (`:low`, `retry_on RetryableError`, `discard_on RecordNotFound`, `Chewy.strategy(:atomic)`) and `granola_sync_all_job.rb`, and register `GranolaSyncAllJob` every 15 minutes in `config/initializers/sidekiq.rb` next to `SchedulerPollingJob`; hook "Sync now" and the 90-day backfill on connect to `GranolaSyncJob`; verify `GranolaSyncAllJob.perform_now` enqueues one job per `connected` connection only
- [ ] 2.9 Add the "How meetings are matched" section to the user guide; verify with `UserGuideLint`
- [ ] 2.10 Write `features/core/granola/granola_sync.feature` (`@sync-http`) covering worked examples H2, H3, E1, E2, E3, E4, E5. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/granola/granola_sync.feature` and confirm it passes before starting phase 3

## 3. Granola Inbox (review, file, discard, re-match)

- [ ] 3.1 Create `granola_meeting_policy.rb` (Scope mirroring `NotePolicy::Scope`; `show?`/`file?`/`discard?`/`rematch?`); verify in `rails runner` that a non-admin's scope returns only meetings with their `user_id`
- [ ] 3.2 Create `granola_meetings_controller.rb` (`index` with status tabs and batched candidate-name lookup, `file`, `discard`, `rematch`, `rematch_all`) and a thin `GranolaRematchJob`; add routes; verify `bin/rails routes | grep granola_meetings`
- [ ] 3.3 Create `granola_meetings/index.html.erb`, `_granola_meeting.html.erb` and turbo-stream responses (row removed on file/discard, replaced on re-match; File disabled until an investor is chosen; "Other investor" reuses the existing investor select); verify in dev that filing removes the row without a reload
- [ ] 3.4 Add the "Granola Inbox" link with the `needs_review` count badge under the Investors menu (policy-gated, shown only when the entity has a connection); verify it appears for an admin and shows the right count
- [ ] 3.5 Add the "Reviewing meetings" section (inbox, ignored tab, re-match) to the user guide; verify with `UserGuideLint`
- [ ] 3.6 Write `features/core/granola/granola_inbox.feature` (`@sync-http`) covering worked examples H4, H5, E8, E9, E10, X6, X7. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/granola/granola_inbox.feature` and confirm it passes before starting phase 4

## 4. Granola updates, edit ownership and failure alerting

- [ ] 4.1 Implement `GranolaNoteFiler.refresh` (update only existing, non-detached notes; recompute digest; never create for ids already in `filed_investor_ids`) and route `filed` meetings to it in the processor; verify in `rails runner` that editing a note's details makes `granola_detached?` true and a refresh leaves it unchanged
- [ ] 4.2 Implement `GranolaConnection#record_failure!` (auth → `needs_attention` + notify; transient → notify once when `last_success_at` is older than 24h, tracked by `failure_notified_at`; reset on success), skip `needs_attention` connections in `syncable`, and make reconnect via `update` resume from the existing `cursor_at`; verify in `rails runner` with a stubbed 401
- [ ] 4.3 Create `GranolaConnectionFailedNotifier < BaseNotifier` and `GranolaMailer#connection_failed` (+ view), following `KpiReportImportFailedNotifier`; verify with a mailer preview or `rails runner` that the email renders dates via bare `l(...)` (email format) and the in-app message links to the profile or entity settings
- [ ] 4.4 Add the "When Granola changes a meeting" and "Troubleshooting a connection" sections to the user guide; verify with `UserGuideLint`
- [ ] 4.5 Write `features/core/granola/granola_updates.feature` (`@sync-http`) covering worked examples H6, E6, E7, X4, X5. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/granola/granola_updates.feature` and confirm it passes
- [ ] 4.6 (QA, not the apply agent) Run [qa-checklist.md](qa-checklist.md) on a staging build and record the
      Sign-off row. Every H/E/X/J/R/C row is Pass, or has a linked defect.
