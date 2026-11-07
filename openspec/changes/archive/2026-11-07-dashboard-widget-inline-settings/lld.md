# Widget settings in place — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/ui/dashboard-widgets/spec.md) · [Tasks](tasks.md)

> **Planning phase — no code changes.** Adds to [design.md](design.md); links rather than repeats.

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
- [Changed during the build](#changed-during-the-build)
- [Sign-off](#sign-off)

---

## Review Summary

- Two collection actions with narrow params instead of reusing `update` — [Controllers](#controllers-params-and-responses), design [D2](design.md#d2-new-settings--save_settings-actions-narrow-params).
- Entity row lock to serialise the first save on defaults — [Transactions](#transactions-locking-and-concurrency), design [D3](design.md#d3-defaults-saved-inside-the-save-under-an-entity-lock).
- `DashboardWidget.default_widgets_for` extracted from the helper (behaviour unchanged) — [Method Contracts](#method-contracts).
- `only_widget` filter in two loops; reload through the page URL — design [D4](design.md#d4-reload-via-the-page-url--only_widget).
- New policy predicate `inline_settings?`; `update?` untouched — [Security Review](#security-review).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① | `app/packs/core/base/views/dashboard_widgets/_settings_button.html.erb` | New | Icon link per widget |
| ① | `app/packs/core/base/helpers/dashboard_widgets_helper.rb` | Modified | `widget_settings_params(widget, dashboard_name, layout)`, `widget_settings_allowed?` (memoised), `widget_frame_key`; `configured_dashboard_widgets` calls `default_widgets_for` |
| ① | `app/packs/core/base/policies/dashboard_widget_policy.rb` | Modified | `inline_settings?` |
| ② | `app/packs/core/base/views/dashboard_widgets/_settings_modal.html.erb` | New | Modal + frame `widget_settings` |
| ②⑦ | `app/javascript/controllers/widget_settings_controller.js` | New | Open/close, saved marker, frame reload, scroll restore, toast, motion |
| ③ | `app/packs/core/base/controllers/dashboard_widgets_controller.rb` | Modified | `settings`, `save_settings`, `settings_target` |
| ③ | `app/packs/core/base/views/dashboard_widgets/settings.html.erb` | New | Form in frame (reuses `_metadata_fields`) |
| ④ | `app/packs/core/base/services/dashboard_widget_settings_save.rb` | New | Defaults-first save |
| ④ | `app/packs/core/base/views/dashboard_widgets/_settings_saved.html.erb` | New | Saved marker |
| ④ | `app/packs/core/base/models/dashboard_widget.rb` | Modified | `self.default_widgets_for(dashboard_name)`, `SIZES` constant |
| ⑥ | `app/packs/core/base/views/dashboard_widgets/_dashboard.html.erb` | Modified | Frame per widget, `only_widget`, icon, modal |
| ⑥ | `app/packs/core/investors/views/investors/multi_portfolio_dashboard.html.erb` | Modified | Same as above |
| ⑦ | `app/assets/stylesheets/custom/widget_settings.scss` (+ import) | New | Motion |
| — | `config/routes/*` (dashboard_widgets collection) | Modified | `get :settings`, `patch :save_settings` |
| Tests | `features/core/dashboard_widget_inline_settings.feature`, `features/security/dashboard_widget_inline_settings_isolation.feature`, `features/step_definitions/dashboard_widget_inline_settings_steps.rb` | New | H/E/X |

**Reviewer checks**
- [ ] No file outside `core/base` except the Aggregated view, JS controller and scss
- [ ] The 97 widget partials are not edited

---

## Schema Detail

N/A — no schema change.

**Reviewer checks**
- [ ] No migration in the diff

---

## Method Contracts

| Method | Signature | Returns | Notes |
|---|---|---|---|
| `DashboardWidget.default_widgets_for` | `(dashboard_name) → Array<DashboardWidget>` | Unsaved catalogue entries | Landing pages (FM/LP/Ops) → first 4; others → all. Same as today's helper branch |
| `DashboardWidgetSettingsSave.call` | `(user:, dashboard_name:, layout:, widget_name:, widget_id:, metadata:, size:) → Result(widget:, refresh:, errors:)` | `refresh` ∈ `:widget, :page` | Transaction; see below |
| `DashboardWidgetPolicy#inline_settings?` | `→ Boolean` | `update? && !user.curr_role_investor?` | For defaults: record = `DashboardWidget.new(entity_id: user.entity_id, dashboard_name:, name: layout)` |
| `DashboardWidgetsHelper#widget_frame_key` | `(widget) → String` | `"#{widget_name.parameterize.underscore}_#{position}"` | Same as today's container id |
| `DashboardWidgetsHelper#widget_settings_allowed?` | `(dashboard_name, layout, lp:) → Boolean` | memoised per request | One policy call per page |

- `DashboardWidgetSettingsSave` steps: (1) validate `size ∈ DashboardWidget::SIZES` (error on `:size`);
  (2) if no saved widget for `(entity, dashboard_name, layout)`: lock entity, re-check, insert
  `default_widgets_for` with `position: index + 1`, `enabled: true`, `display_name: true`, `show_menu: true`,
  `tags: widget_name`, catalogue `size`; (3) find target (saved id, or the just-saved row with that
  `widget_name`); (4) `update(metadata:, size:)`; failure → raise rollback, return errors.
- `refresh: :page` when step 2 ran; else `:widget`.

**Reviewer checks**
- [ ] `configured_dashboard_widgets` returns the same hash before/after the extraction (H5, E4)
- [ ] `metadata: ""` saves as blank (widget defaults apply) — E3
- [ ] Keys not in the hints survive a save (form posts them back) — E9

---

## Controllers, Params and Responses

| Action | Route | Loads | Authorize | Params | Success | Failure |
|---|---|---|---|---|---|---|
| `settings` | `GET /dashboard_widgets/settings` | `widget_id` → `policy_scope(DashboardWidget).find`; else catalogue lookup | `:inline_settings?` | `widget_id` or `dashboard_name, layout, widget_name` | 200 frame form | 404 unknown name / id; 403 policy |
| `save_settings` | `PATCH /dashboard_widgets/save_settings` | same | `:inline_settings?` | above + `dashboard_widget[metadata, size]` | 200 frame `_settings_saved` | 422 frame form with errors; 403; 404 |

- Catalogue lookup: `DashboardWidget::WIDGETS.fetch(dashboard_name) { not_found }.find { _1.widget_name == widget_name } || not_found`.
- `layout` defaults to `"Default"`; max 100 chars (model rule).
- Both actions render without the app layout inside the frame (`layout false` for these two actions).

**Reviewer checks**
- [ ] `verify_authorized` covers both actions (no new exclusion)
- [ ] Strong params: only `metadata`, `size`
- [ ] 422 re-renders inside the frame (Turbo shows it)

---

## Queries and Indexes

| Query | Shape | Index |
|---|---|---|
| Layout has saved widgets? | `DashboardWidget.where(entity_id:, dashboard_name:, name:).exists?` | existing (entity_id) |
| Load target | `policy_scope(DashboardWidget).find(id)` | PK |
| Defaults insert | ≤ ~20 `create!` (validations + callbacks) | — |

**Reviewer checks**
- [ ] No query inside the dashboard widget loop for the icon (policy memoised)
- [ ] `PROSOPITE=1` clean for the feature

---

## Transactions, Locking and Concurrency

- `ActiveRecord::Base.transaction` around steps 2–4.
- `Entity.lock.find(user.entity_id)` (`SELECT … FOR UPDATE`) only before step 2; re-check `exists?` after the lock.
- Double click: the button is disabled on submit; a second identical PATCH is a no-op update (E6 covers two
  first saves).
- Concurrent edits of the same saved widget: last write wins (as the edit page).

**Reviewer checks**
- [ ] The lock is taken only when the layout had no saved widget
- [ ] Re-check after lock prevents duplicate defaults (E6)

---

## Background Jobs

N/A — none.

**Reviewer checks**
- [ ] No job enqueued

---

## External Integrations

N/A — none.

**Reviewer checks**
- [ ] No external call

---

## Error Mapping and Logging

| Condition | HTTP | User sees |
|---|---|---|
| Unknown dashboard/widget name or id | 404 | Frame "Content missing" replaced by the controller with "This widget could not be found" |
| Not allowed | 403 | Same, "You cannot change this widget" |
| Size not allowed | 422 | "Size is not one of XL, Large, Medium, Small, XS" |
| Metadata not a literal | 422 | The model's existing message |
| Frame reload fails | — | "Could not refresh — reload the page" in the widget |

**Reviewer checks**
- [ ] No params logged beyond Rails defaults

---

## Security Review

| Action | Policy method | Load scope | Permitted params | Scenario |
|---|---|---|---|---|
| `settings` | `DashboardWidgetPolicy#inline_settings?` | `policy_scope(DashboardWidget)`; catalogue allowlist | `widget_id`, `dashboard_name`, `layout`, `widget_name` | X1, X2, X6 |
| `save_settings` | same | same | + `dashboard_widget[metadata, size]` | X1, X2, X4, X5, X7 |
| Icon render | same (memoised) | — | — | X1, X3 |

- `entity_id` of new default rows comes from `current_user.entity_id`, never params.
- `only_widget` is compared to keys built server-side; never used in SQL or paths.

**Reviewer checks**
- [ ] Brakeman: no new warnings
- [ ] `features/security/dashboard_widget_inline_settings_isolation.feature` green

---

## Configuration and Rollout

- No flag; additive UI for all firms. Reverting = removing the icon partial render.

**Reviewer checks**
- [ ] No credentials or env changes

---

## Test Plumbing

- Playwright for the popup scenarios (default driver); `@rack_test` for direct-request security rows.
- Reduced motion (E7): `page.driver.with_playwright_page { _1.emulate_media(reducedMotion: "reduce") }`.
- "Not reloaded" check (H3): set a `data-test-marker` on another widget via JS before saving, assert it remains.
- Distinct `TEST_ENV_NUMBER` per run.

**Reviewer checks**
- [ ] Every H/E/X has exactly one scenario with `# ID —`

---

## Project Rules Checklist

| Rule | Applies | How |
|---|---|---|
| Large-table hygiene | N/A | `dashboard_widgets` is small |
| No `blank?/present?` on relations | Applies | `exists?` for the layout check |
| Dedup in SQL | N/A | — |
| Date formatting | N/A | No dates shown |
| Tenant scoping | Applies | policy_scope + entity from user |
| MCP ontology | N/A | No MCP tool touched |
| IRM cops | Applies | RuboCop clean |
| Cucumber only | Applies | No RSpec |
| SQLite vs MySQL | Applies | Lock query is MySQL `FOR UPDATE`; SQLite ignores it — E6 runs sequentially in tests |

**Reviewer checks**
- [ ] Each Applies row verified in the diff

---

## Changed during the build

| Log # | What changed | Why |
|---|---|---|
| B1 | The popup became a right-side panel (Bootstrap offcanvas, 480px) with a light header, one compact column of fields that scrolls and a pinned footer | User review: the centred modal overflowed the screen and looked heavy |
| B2 | Panel fields (compact mode of `_metadata_fields`, panel only): an icon per kind of setting and an ⓘ tooltip carrying the hint; a one-line tip "Leave a setting empty…"; header note shortened to one line with the full text in a tooltip | User review: no icons, tooltips or guidance |
| B3 | Footer: icon link to the full page, text Cancel, small pill "Save" (tooltip "Save, then reload this widget in place") | User review: buttons too large and blocky |
| B4 | Panel tooltips are created inside the panel (`data-bs-container`) | The theme's offcanvas z-index (105555) hid body-level tooltips |
| B5 | Panel width is `width: 480px; max-width: 100vw` (no CSS `min()`) | The app's Sass compiler evaluates `min()` and fails on px vs vw |
| B6 | The settings icon floats on the card's top-right corner instead of inside its header | It covered widgets' own header buttons (e.g. the portfolio report grid) |
| B7 | Esc closes the panel wherever focus is | Bootstrap's Esc only works with focus inside the panel |
| B8 | An unknown dashboard / widget name answers with the app's not-found redirect (302), not 404 | The app's global RecordNotFound handling; still refused, nothing saved (X6) |
| B9 | Dashboard widget cards holding the portfolio AG grid get their card padding back | Existing scaffolds.scss rule removed it for the full-page grid; on dashboards the grid ran edge to edge |

---

## Sign-off

| Reviewer | Date | Decision |
|---|---|---|
| | | |
