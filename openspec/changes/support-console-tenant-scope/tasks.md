# Tasks

Worked examples are in [design.md](design.md#worked-examples); files and contracts in [lld.md](lld.md).
Node tests are named `tenant-scope <ID> — …`; each Cucumber scenario runs them with
"the support machine tests matching "tenant-scope <ID> —" run" / "they pass", and carries an
`# <ID> — …` comment.

## 1. Link list

- [x] 1.1 `SupportConsoleCodeArchive.join_map` + write `join_map.json` in `build` (LLD Method Contracts); verify: building an archive locally produces the file with `doc_shares.document_id → documents`
- [x] 1.2 `tables.loadJoinMap` (empty when missing) and `check.js` ✓/✗ line (LLD File Map); verify: `npm test` green
- [x] 1.3 Write `features/support_console/tenant_scope.feature` scenarios H7, E6, X8 and run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/support_console/tenant_scope.feature` until green before phase 2

## 2. Real-link rule and deny list

- [x] 2.1 `prepareStatement` fifth argument; link rule in `anchors` (fk = id either order, parent ← child, polymorphic with class, IN column); `linksFor` refusal text; `__scope_` reserved (LLD Method Contracts, Error Mapping); verify: node tests pass
- [x] 2.2 `DENIED_TABLES` += `agent_chat_sessions`, `agent_chat_messages`; hook passes the map; brief gains the join line; verify: `npm test` green
- [x] 2.3 Add scenarios H2, H3, E1, E2, E7, E8, E10, E11, X1–X6, X9 to `tenant_scope.feature` and run it with `TEST_ENV_NUMBER=$RANDOM` until green before phase 3

## 3. Hidden scope columns and row check

- [x] 3.1 `addScopeColumns` for plain, grouped, DISTINCT and UNION shapes; refuse others "unreadable" (LLD Method Contracts); verify: node tests pass
- [x] 3.2 `heldBack` replaces `flagRows` in `db.js`; held-back event `blocked`, `flagged`, reason "rows from another client"; strip `__scope_*` (LLD Error Mapping); verify: node tests pass
- [x] 3.3 Add scenarios H1, H4, H5, H6, E3, E4, E5, E9, E12, E13, E14, X7, X10, X11 to `tenant_scope.feature`; run it and `features/support_console/` with `TEST_ENV_NUMBER=$RANDOM` until green; rubocop clean
- [x] 3.4 Update `docs/modules/ai/support_console/technical_guide.md` (data access safety) and the `support-console` design's known-gap note

## 4. Rollout

- [ ] 4.1 Deploy to staging; `support_console:machine_check[staging.in]` shows ✓ link list
- [ ] 4.2 (QA) Run [qa-checklist.md](qa-checklist.md) on the staging build and record the sign-off
