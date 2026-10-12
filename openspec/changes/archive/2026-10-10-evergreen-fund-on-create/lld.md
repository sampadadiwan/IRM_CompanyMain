# Choose Closed-end or Open-ended When Creating a Fund — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Tasks](tasks.md)

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

- **One transaction for the fund and its terms** (`EvergreenFundCreate`). Check the rollback
  covers the class terms and the seeded journeys. See [Transactions](#transactions-locking-and-concurrency).
- **Step ids are offset.** The shared `_steps` partial takes `offset:` (0 on Evergreen Settings, 2
  on New Fund), so the `step-N` ids and the Review "Edit" links don't collide with the fund form's
  step-1 and step-2.
- **Presets fill on the client** from a JSON endpoint, so unsaved values on New Fund aren't lost
  and no fund id is needed.
- **Removing the switch routes** (`create`, `destroy` on `resource :settings`).

**Reviewer checks**
- [ ] No caller of `evergreen_settings_path(..., method: :post/:delete)` remains

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① | `app/packs/funds/funds/views/funds/_form.html.erb` | Modified | Fund type radio, Back buttons, evergreen steps, Create fund button |
| ① | `app/javascript/controllers/fund_type_controller.js` | New | Show or hide the evergreen steps and buttons |
| ② | `app/packs/funds/evergreen/views/evergreen/settings/_steps.html.erb` | New (extracted) | The evergreen wizard steps, with `offset:` |
| ② | `app/packs/funds/evergreen/views/evergreen/settings/_class_term_card.html.erb` | New (extracted) | One class card; also rendered into a `<template>` |
| ② | `app/javascript/controllers/evergreen_settings_controller.js` | Modified | `applyPreset` fills from JSON; `syncClasses` builds cards from Unit Types |
| ② | `app/packs/funds/evergreen/controllers/evergreen/presets_controller.rb`, `config/routes/fund.rb` | New / Modified | `GET /evergreen_presets/:name` (JSON) |
| ③ | `app/packs/funds/funds/controllers/funds_controller.rb` | Modified | `open_ended_requested?`, hand-off to ④, `@evergreen_setting` for the form |
| ③ | `app/packs/funds/evergreen/controllers/concerns/evergreen_setting_params.rb` | New (moved) | `permitted` / `setting_attributes` from `SettingsController` |
| ④ | `app/packs/funds/evergreen/services/evergreen_fund_create.rb` | New | Transaction: fund save + `EvergreenEnable` |
| ④ | `app/packs/funds/evergreen/models/evergreen_fund_setting.rb` | Modified | On create, each class needs a starting price (X2) |
| ⑤ | `config/routes/fund.rb`, `evergreen/settings_controller.rb`, `services/evergreen_disable.rb`, `funds/views/funds/show.html.erb`, `evergreen/settings/show.html.erb` | Modified / Deleted | Switch paths removed |
| ⑥ | `evergreen/settings/show.html.erb`, `settings_controller.rb` | Modified | Renders `_steps`; redirects for non-evergreen funds |
| docs | `docs/user_guides/evergreen_funds_user_guide.md`, `docs/modules/funds/evergreen_business_rules.md` | Modified | "Creating an open-ended fund" |
| tests | `features/fund/evergreen/evergreen_fund_on_create.feature`, `features/step_definitions/evergreen_fund_on_create_steps.rb`, `features/fund/evergreen/settings.feature`, `evergreen_edge_nav_steps.rb`, `openspec/changes/open-ended-funds/design.md` | New / Modified | New scenarios; retired ones removed |

---

## Schema Detail

N/A. No schema change.

---

## Method Contracts

**`EvergreenFundCreate`** (Trailblazer)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(fund:, setting_params:, current_user:)` | An unsaved `Fund`, the parsed setting attributes | ctx with `success?`; `ctx[:errors]` (Array of messages) on failure | — | Inserts the fund, setting, class terms and journey templates | No (creates) |

**`EvergreenSettingParams`** (controller concern)

| Method | Returns |
|---|---|
| `evergreen_setting_attributes` | Today's `setting_attributes` hash |
| `evergreen_setting_attributes_for_update` | Today's `setting_attributes_for_update` hash |

**Reviewer checks**
- [ ] `SettingsController#update` behaviour is byte-identical after the move

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `FundsController#create` | `fund_params` (unchanged) + `params[:fund_type]` + `evergreen_fund_setting[...]` (via the concern) | `create?` | Redirect to the fund | `render :new` 422 with fund and setting errors |
| `Evergreen::PresetsController#show` | `name` | the user's entity has evergreen on | JSON values | 404 |
| `Evergreen::SettingsController#show/#update` | unchanged | unchanged | unchanged | Non-evergreen fund → redirect to the fund with the message |

---

## Queries and Indexes

N/A. No new list queries.

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| Create an open-ended fund | Fund insert, setting, class terms, journey seeding | none | A fund without terms | — |

**Reviewer checks**
- [ ] `ActiveRecord::Rollback` is raised when `EvergreenEnable` fails, and `@fund` is reset to a
  new record for the re-render

---

## Background Jobs

N/A.

---

## External Integrations

N/A.

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `ActiveRecord::RecordInvalid` (fund) | `fund.save!` | `EvergreenFundCreate` | Fund errors on the form | No |
| `EvergreenEnable` failure | operation | `EvergreenFundCreate` (rollback) | Setting errors on the form | No |
| `EvergreenFormParsing::BadDates` | params parsing | `FundsController#create` | The message on the form | No |

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `create?` unchanged; presets need the evergreen switch |
| Tenant isolation | `entity_id` pinned as today |
| Mass assignment | `fund_type` is not in `fund_params` |
| Removed surface | The switch routes are deleted |

---

## Configuration and Rollout

| Item | Value |
|---|---|
| Feature flag | Existing `enable_evergreen_funds` |
| Rollback | Revert the code; no data changed |

---

## Test Plumbing

| Feature file | Steps |
|---|---|
| `features/fund/evergreen/evergreen_fund_on_create.feature` | New: `I start a new fund`, `I choose fund type {string}`, `I fill the open-ended wizard with …`, `I click Back`; reused: login and evergreen steps |

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations | Applies | none added |
| Dates via `l()` | N/A | — |
| Pundit on every action | Applies | `PresetsController` authorizes |
| Cucumber only; distinct `TEST_ENV_NUMBER` | Applies | One feature |
| Rubocop clean | Applies | Per phase |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
