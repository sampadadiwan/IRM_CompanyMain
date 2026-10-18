# API gaps (report only — do not patch; the APIs belong to another workstream)

> **Status 2026-10-18:** G8–G10, G12, G13, P1–P11 are being fixed on branch `worktree-funds-api-review`
> (openspec change `funds-json-api-hardening`, phase 8 — not merged, feature not yet green). Re-check each before
> relying on the workaround. Full handoff: `docs/modules/ai/client_onboarding/api_improvements_from_orios_trial.md`.

| # | Gap | Impact on onboarding | Found |
|---|---|---|---|
| G1 | No validate-only / dry-run mode for imports | Errors surface only after rows are written; agent must pre-validate against templates | 2026-10-18 |
| G2 | Feature flags (`permissions`) are admin-managed; no ops-facing endpoint confirmed | Ops sets flags in `/admin/entities`; agent only proposes | 2026-10-18 |
| G3 | **Fixed in funds-json-api-hardening (P10): non-support users' `permissions` are now dropped.** Was: `EntitiesController#entity_params` permits `permissions: []`, and `EntityPolicy#update?` allows the entity's company_admin — a company admin may be able to set chargeable flags via `PATCH /entities/:id.json` | Possible security issue; raise with the API owner, do not rely on it | 2026-10-18 |
| G4 | No entity-wide email switch other than sandbox; per-access `InvestorAccess.email_disabled` only | Sandbox is the only guard; must stay on throughout | 2026-10-18 |
| G6 | No way to attribute an API write to an agent run or an approval — `audits` rows show only the token's user | Agent vs human actions are indistinguishable in `audits`; the journal (v1) and `agent_actions` (later) fill this | 2026-10-18 |
| G7 | Support impersonation (`UsersController#login_as`, records `session[:support_user_id]`) is browser-session only; bearer-token requests cannot act as a client user or record the real actor | Agent must use an ops user that is itself a member of the client entity | 2026-10-18 |
| G8 | **Blocking — for the API owner.** `_import_upload.json.jbuilder` exposes only id/type/status/error_text; lacks `total_rows_count`, `processed_row_count`, `failed_row_count`, `custom_fields_created` and a URL to the results file (per-row errors) | Agent cannot tell whether an import worked or which rows failed | 2026-10-18 |
| G9 | **Blocking — for the API owner.** `_entity.json.jbuilder` exposes no `entity_setting` (sandbox, sandbox_emails, KYC doc lists, mcp_enabled). Writing them via `PATCH /entities/:id.json` works | The sandbox-before-every-write guard cannot read sandbox | 2026-10-18 |
| G10 | For the API owner (minor). `ImportUploadsController#delete_data` only `redirect_to`s; no JSON response | Undo runs but returns a 302, not a confirmation | 2026-10-18 |
| G5 | Existing MCP server (`app/packs/ai/mcp_server`) is read-only (23 `list_*`/`get_*` tools) | Onboarding tools must call website `.json` endpoints instead | 2026-10-18 |

## Found in the Orios trial (2026-10-18) — app bugs, report only

| # | Issue | Evidence | Impact |
|---|---|---|---|
| B1 | **Fund import is broken**: `ImportFund#save_row(row_data, import_upload, _cf)` takes 3 args, `ImportUtil#process_row` passes 4 | import_fund.rb:8, import_util.rb:225; "wrong number of arguments (given 4, expected 3)" | No fund can be created by import (UI or API). Used `POST /funds.json` instead |
| B2 | **Fund JSON 500**: `_fund.json.jbuilder` line 11 calls `tracking_co_invest_call_amount`, undefined on Fund | `POST /funds.json` created the fund but answered 500; `GET /funds.json` returns nothing usable | Fund API unusable for reads — for the funds-API owner |
| B3 | **Rollup drift after payment import + bulk verify**: fund collected ₹300.25 Cr vs ₹300.00 Cr in remittances; commitment 055 ₹1.5 Cr vs ₹2.0 Cr | entity 1629, fund 375, commitment 2548 | Fund/commitment totals on screens are wrong. **Root cause confirmed:** the payment import's recount (`perform_now`, on `default`) raced bulk-verify deltas; see handoff P6 |
| G11 | No way to delete an entity (FK cycle entities.root_folder_id ↔ folders.entity_id) | destroy raised InvalidForeignKey | Failed onboardings leave shells |
| G12 | `PATCH /entities/:id.json` with `entity_setting_attributes` but no id creates a **second** entity_settings row; the id is not exposed (G9) and patching the old id → 403 | entity 1629 has settings rows 1629 (empty) and 1630 (sandbox on) | Which row `has_one` returns is unordered → sandbox could read as off |
| G13 | Upload status "Completed" even when every row failed | uploads 2662, 2663 | API clients cannot rely on status (with G8) |
| G14 | Results file had only the header row for fully-failed uploads; the per-row error existed only in the log | uploads 2662, 2663 | Errors invisible to users and the API |
| G15 | **Verified safe (2026-10-18): `FormTypePolicy#create?` requires `belongs_to_entity?`.** Was: `FormTypesController#form_type_params` permits `:entity_id` (`entity_id ||= current_user.entity_id`) — **to verify** whether a user can create form types in another entity | form_types_controller.rb:194 | Possible tenant-isolation gap |
