# Tasks

> **Reproduce first.** Phase 1 writes the Cucumber scenarios from the report's Verification
> table that fail against the CURRENT code, and runs them to watch them fail.

> **Phase gate:** each numbered group is a phase. A phase's last task runs its Cucumber feature
> green before the next phase starts.

> **Every cucumber run needs a fresh `TEST_ENV_NUMBER`** and **local Redis on 6379**. Launch in
> the background and `wait $pid`.

## 1. Reproduce

- [x] 1.1 Write `features/misc/dr_search_indexes.feature` + `features/step_definitions/dr_search_indexes_steps.rb` covering H1–H3, E1–E5, X1–X5. Steps call `Dr::SearchIndexes` (discovery, exclusions, grading). X5 reads `lib/tasks/dr_fix_db.rake` and `config/deploy.rb` as text. Scenario comments carry "ID — Edge case: …".
- [x] 1.2 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/misc/dr_search_indexes.feature`. Confirm X3/X5/H1 fail against current code (no `Dr::SearchIndexes`; `deploy:chewy_reset` still printed). Record the output.
      - Recorded 2026-11-08: `13 scenarios (13 failed)`: 12 × `uninitialized constant Dr::SearchIndexes`, X5 on `deploy:chewy_reset` still printed.

## 2. Fix — discovery, grading, reindex task (report Fix rows 1, 2, 3)

- [x] 2.1 `lib/dr/search_indexes.rb`: `discover` (glob `app/packs/**/models/*_index.rb`, constantize, keep `< Chewy::Index`, sort), `EXCLUDED = { "AccountEntryIndex" => reason }`, `indexes`, `db_count(index)` via `index.adapter.default_scope.count`, `grade(index:, es:, db:, imported:, exact:)` → `Dr::BackupSchedule::Grade`-style ok/fail. Inline comments on every step. Verify: `bin/rails runner 'p Dr::SearchIndexes.indexes.size'` prints 29.
- [x] 2.2 `lib/tasks/dr_reindex.rake` `dr:reindex_search`: for each index `reset!` (rescue per index and keep going), refresh, ES count via the client, grade exact, print a table (index, MySQL, ES, seconds, result) plus skipped exclusions, `abort` on any failure. Verify: `ruby -c`; a local run against dev ES `RAILS_ENV=development bundle exec rake dr:reindex_search` finishes with every row ok (local ES only).
- [x] 2.3 `config/deploy.rb` `recovery:reindex_search` (roles :primary, `execute :rake, "dr:reindex_search RAILS_ENV=…"`). Verify: `bundle exec cap -T 2>/dev/null | grep reindex_search` lists it.
- [x] 2.4 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/misc/dr_search_indexes.feature` and confirm H1–H3, E1–E5, X1–X4 pass (X5 needs phase 3).

## 3. Fix — wire into DR, verify, follow-ups, docs (report Fix rows 4–7)

- [x] 3.1 `aws_utils.rb` `setup_infra`: new `dr_phase "Phase 8/9 · Rebuild the search index"` running `cap recovery:reindex_search` after the restore tasks and before `nginx:switch_app`, in both modes. Renumber every phase label to `/9`. Verify: `ruby -c`; `grep -c 'Phase [0-9]/9'` = 9.
- [x] 3.2 `dr_verify.rake`: "Search index populated" check — every DR-owned index graded tolerant (ES vs MySQL scope count). Verify: `ruby -c`.
- [x] 3.3 `dr_fix_db.rake:261,323,425`: print `bundle exec cap <stage> recovery:reindex_search`. Verify: `grep -c chewy_reset lib/tasks/dr_fix_db.rake` = 0.
- [x] 3.4 Docs: `dr_guide.md` §5 sequence diagram gains the reindex step; §10 adds what is and isn't rebuilt (AccountEntryIndex and why) and that `rake chewy:reset` finds no indexes here. Mermaid lint passes. Update `gap_review_2026_11.md` G4 (ES half: fixed in code).
- [x] 3.5 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/misc/dr_search_indexes.feature` and confirm all IDs, X5 included, pass.

- [x] 3.6 (after the first batch drill, 2026-11-08) `AmlReportIndex` built from `custom_name`; index problems WARN, never fail the run (`Dr::SearchIndexes.verdict` in the rebuild step and in verify); feature rows E8, H4, H5. See report "Changed during the build".

## 4. Regression and cleanup

- [x] 4.1 Run `features/misc/dr_search_indexes.feature` and `features/misc/dr_backup_schedule.feature` together (both DR features) and confirm green.
- [ ] 4.2 Blast-radius callers (`setup_infra`, `recovery:verify`, `dr:fix:*`) need AWS: covered by the batch staging drill (qa-checklist B1, H1–H3, R1–R3, X3).
- [x] 4.3 `bundle exec rubocop` on new files plus changed lines of `aws_utils.rb`, `dr_verify.rake`, `dr_fix_db.rake`, `config/deploy.rb`: clean.
- [x] 4.4 N+1 check: not applicable — no request path or job; the reindex batches through Chewy's importer.
- [x] 4.5 UI check: not applicable — no screens touched.
