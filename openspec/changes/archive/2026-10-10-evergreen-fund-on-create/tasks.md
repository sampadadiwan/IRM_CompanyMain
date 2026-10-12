# Tasks

> **Phase gate:** each phase ends with its Cucumber feature green before the next starts.
> Fresh `TEST_ENV_NUMBER` per run; Redis up; rubocop per phase; IDs in code comments; never commit.

## 1. Shared steps, presets and removing the switch (boxes ② ⑤ ⑥)

- [x] 1.1 Extract `evergreen/settings/_steps.html.erb` (with `offset:`) and `_class_term_card.html.erb`
      from `settings/show`; `settings/show` renders them. Verify: Evergreen Settings looks the same.
- [x] 1.2 Add `Evergreen::PresetsController#show` (JSON) and its route; `applyPreset` fills fields
      from it and marks the chosen summary ✓. Verify: picking a preset on Evergreen Settings fills
      the form.
- [x] 1.3 Remove the switch: `create` and `destroy` routes and actions, `EvergreenDisable`, "Make
      closed-end again", the fund menu item for non-evergreen funds; `show` for a non-evergreen
      fund redirects with the message. Move `permitted` / `setting_attributes` into
      `EvergreenSettingParams`.
- [x] 1.4 Rework `features/fund/evergreen/settings.feature`: drop H1, X1, X4, E138, X83 (mark
      them "Retired — evergreen-fund-on-create" in open-ended-funds design.md); the remaining
      scenarios use an evergreen fund. Drop the `EvergreenDisable` step. Run settings.feature green.

## 2. New Fund: type, steps, create (boxes ① ③ ④)

- [x] 2.1 `EvergreenFundCreate` and the starting-price check on create (X2).
- [x] 2.2 `FundsController#create` / `#new` (`open_ended_requested?`, `@evergreen_setting`).
- [x] 2.3 `funds/_form`: Fund type radio, Back buttons, evergreen steps (`offset: 2`), class-card
      template, Create fund button; `fund_type_controller.js`; `syncClasses`.
- [x] 2.4 Edit form shows the type read-only.
- [x] 2.5 Docs: the user guide's "Creating an open-ended fund" and business rules section 2.
- [x] 2.6 Write `features/fund/evergreen/evergreen_fund_on_create.feature` (H1–H5, E1–E6, X1–X5)
      and run it green, then the full evergreen suite plus `features/fund/xfund.feature`, green.
      Done: evergreen_fund_on_create 15/15, settings 8/8, xfund 10/10 (2026-10-09). Pending: the
      full evergreen suite (`pcuc features/fund/evergreen`).
- [x] 2.7 Edit Fund on an open-ended fund carries on into its open-ended terms (same steps as
      create, **Save fund** saves the fund and terms together); a unit type added on edit adds a
      class card, and saved classes are never removed by the sync (H4). Evergreen funds' Actions
      menu gains **Edit Fund**.
- [x] 2.8 Funds list: an Open-ended / Closed-ended badge in the Tag List column (and card view),
      derived from the fund's type, one query per page, snapshot rows resolved to their live fund.
- [x] 2.9 Wording: "Closed-ended" (not "Closed-end") beside "Open-ended" on screens, tests and docs.
- [x] 2.10 Docs: user guide "Editing an open-ended fund" and "Telling the two types apart", two FAQs.
- [x] 2.11 New Fund opens on a type page (H5): Closed-ended and Open-ended cards describing each
      type, Continue once one is picked; step 1 shows the chosen type with Change and Back. Not on
      Edit Fund or for companies without evergreen; a failed create reopens at the fund details.

## 3. Coverage

- [x] 3.1 Coverage: design IDs = feature IDs (H1–H5, E1–E6, X1–X5) — 16 IDs, one scenario each.
- [x] 3.2 (QA) Run qa-checklist.md on a deployed build.
