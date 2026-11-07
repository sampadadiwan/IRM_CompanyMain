# Tasks

> **Phase gate:** each numbered group below is a phase. A phase ends with three tasks, in order:
> (a) **UI review** — screenshot each changed screen next to the reference named in design.md's *Screen
> standards* and apply the UI self-review checklist; (b) **N+1 check** — run the phase's features under
> Prosopite and fix every N+1 in this change's code; (c) run the phase's Cucumber features green. Phase 2 starts
> only once phase 1's features are green. Test runs: `cmd & p=$!; wait $p`, never a `while pgrep` loop.

## 1. Icon, popup and save (server + popup)

- [x] 1.1 `DashboardWidget.default_widgets_for(dashboard_name)` and `SIZES`; `DashboardWidgetsHelper#configured_dashboard_widgets` calls it (LLD › Method Contracts); verify in `bin/rails runner` that the default hash for FM Landing (4) and Portfolio Dashboard (all) is unchanged
- [x] 1.2 `DashboardWidgetPolicy#inline_settings?` (D6); verify in `bin/rails runner` true for a company admin, false after switching to the investor role
- [x] 1.3 Routes + `DashboardWidgetsController#settings` / `#save_settings` with narrow params (D2, LLD › Controllers); verify `bin/rails routes -g dashboard_widgets` lists both
- [x] 1.4 `DashboardWidgetSettingsSave` service: size allowlist, defaults first under the entity lock, update, rollback (D3); verify in `bin/rails runner` against a throwaway layout name in development and delete the rows after
- [x] 1.5 Views: `settings.html.erb` (reuses `_metadata_fields` + `metadata-form`, Size, shared-settings note, no-settings line, full-page link) and `_settings_saved.html.erb` marker; `_settings_modal.html.erb`; `_settings_button.html.erb` (D1); render the icon and modal in `_dashboard.html.erb` and `investors/multi_portfolio_dashboard.html.erb`, never with `lp_context`; verify the icon renders on Fund 11's dashboard on the dev server
- [x] 1.6 `widget_settings_controller.js` (open modal on frame load, close on saved marker, focus return, spinner/disable on submit) — the reload itself comes in phase 2; verify the popup opens and saves on the dev server
- [x] 1.7 Write `features/core/dashboard_widget_inline_settings.feature` (H1, H2, H7, H8, E1, E2, E4, E5, E6, E9, X4, X5) and `features/security/dashboard_widget_inline_settings_isolation.feature` (X1, X2, X3, X6, X7), each scenario with its `# ID —` comment
- [x] 1.8 UI review: screenshot the icon and popup on a 157 dashboard beside the widget edit form (fields) and an existing Bootstrap modal; apply the UI self-review checklist
- [x] 1.9 N+1 check: `PROSOPITE=1 TEST_ENV_NUMBER=$RANDOM bundle exec cucumber` on both features; truncate and read `log/prosopite.log`; fix N+1s in this change's code
- [x] 1.10 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/dashboard_widget_inline_settings.feature features/security/dashboard_widget_inline_settings_isolation.feature` until green

## 2. In-place reload and motion

- [x] 2.1 Wrap each widget in `turbo_frame_tag "dashboard_widget_#{key}"` with `data-widget-size-class`; `only_widget` filter in both loops (D4); verify `?only_widget=valuation_freshness_<n>` on the dev server renders one widget
- [x] 2.2 Controller: on the saved marker, `refresh: widget` → shimmer + set frame `src` (page URL + `only_widget`), swap the container size class on load, fade-in, highlight, toast; `refresh: page` → store scroll, `Turbo.visit(location.href, {action: "replace"})`, restore scroll (D5); empty frame → full refresh; failed load → "Could not refresh — reload the page"; verify on the dev server
- [x] 2.3 `widget_settings.scss`: icon fade, modal rise, shimmer, highlight ring, toast; all off under `prefers-reduced-motion` (D7); theme variables only; verify in light and dark themes
- [x] 2.4 Write `features/core/dashboard_widget_inline_settings_refresh.feature` (H3, H4, H5, H6, E3, E7, E8), each with its `# ID —` comment
- [x] 2.5 UI review: screenshots of the shimmer, the refreshed widget and the toast on a 157 dashboard; check the 15 own-card widgets' icon placement (Fund Stats, Company Charts, Fund Ratios…)
- [x] 2.6 N+1 check: `PROSOPITE=1` run of the refresh feature; fix N+1s in this change's code
- [x] 2.7 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/dashboard_widget_inline_settings_refresh.feature` until green, then re-run the phase 1 features and the 10 dashboard insight features plus `features/misc/multiple_portfolio_dashboard.feature` to confirm nothing regressed

## 3. Coverage, docs and hand-off

- [ ] 3.1 Coverage: the 24 H/E/X IDs in design.md equal the `# ID —` comments in the three feature files
- [ ] 3.2 RuboCop and Brakeman clean on the changed files; `openspec validate dashboard-widget-inline-settings` passes; mermaid lint exit 0
- [ ] 3.3 Dev-DB render check of the 9 dashboards (every widget frame 200, no errors) as fm1@demofund.com
- [x] 3.4 Update design.md / lld.md "Changed during the build" with any deviation
- [ ] 3.5 QA runs qa-checklist.md on a deployed build and records the sign-off (for QA, not the apply agent)

## Apply log

- Phase 1 + 2: 24 scenarios across the three features green; regression with the 10 dashboard insight features and `features/misc/multiple_portfolio_dashboard.feature`: 165/165 green.
- UI reviewed with the user live on the dev server; changes B1–B9 recorded in design.md / lld.md "Changed during the build".
