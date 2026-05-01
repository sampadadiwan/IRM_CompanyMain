# PRD: Named Dashboard Selector

## 1. Overview

This feature exposes named dashboard configurations to end users via a dropdown selector that appears above the dashboard navigation bar. When an entity has more than one named dashboard configured for a given dashboard type, users can switch between them without leaving the page. The selected dashboard is reflected in the URL so it can be bookmarked and shared.

## 2. Background & Problem Statement

The `DashboardWidget` model supports a `name` column (default: `"Default"`) that allows a single entity to have multiple distinct widget layouts for the same dashboard type (e.g., `"Fund Dashboard"`). Today, named dashboards can be created by admins via the Dashboard Widgets admin interface, but there is no way for regular users to discover or switch between them. The only way to load a non-Default dashboard is to manually append `?name=X` to the URL — an approach that is not discoverable or usable in production.

Named dashboards are a powerful configuration capability that is entirely invisible to end users today. This feature makes them visible and usable.

## 3. Goals

- Allow users to switch between named dashboards via a UI control, without a full page reload.
- Keep the selected dashboard reflected in the URL (bookmarkable, shareable).
- Introduce no new database schema changes.
- Apply consistently across all dashboard types (Fund, Investor, Portfolio Company, Aggregated Portfolio, Operations, and Landing Pages).

## 4. Non-Goals

- Creating or editing named dashboards from this UI (that remains an admin-only operation via the Dashboard Widgets CRUD).
- Reordering or renaming dashboards from this UI.
- Any change to how widgets within a dashboard are configured or displayed.

## 5. User Stories

**As an admin who has configured multiple named dashboards for a fund**, I want to be able to switch between them from the fund's dashboard page so that I can compare different widget layouts or scenarios without editing the URL manually.

**As a regular user viewing an investor dashboard**, I want to see a clear dropdown at the top of the page if multiple dashboard configurations exist for this investor, so I know they exist and can select them.

**As a user who bookmarks a named dashboard URL**, I want the page to load the correct named dashboard when I return to that URL so my bookmark stays useful.

## 6. User Requirements

### 6.1 Dropdown Visibility

- A dropdown selector is displayed **above the dashboard navigation bar**, flush left, when the current entity has **more than one** distinct named dashboard configured for the current `dashboard_name + entity_id` combination.
- If only one named dashboard exists (including only "Default"), **no dropdown is shown** and the page behaves exactly as it does today.
- The dropdown lists all named dashboards in **alphabetical order**.
- The currently active dashboard name is **pre-selected** in the dropdown.

### 6.2 Navigation Behaviour

- Selecting a different name from the dropdown navigates to the same page with `?name=<selected>` added or replaced in the URL query string.
- The navigation uses a **Turbo Frame swap** — only the dashboard content area refreshes; the rest of the page (sidebar, header) does not reload.
- The browser URL **updates** to reflect the new `?name=` value so the selected dashboard is bookmarkable and shareable.

### 6.3 Scope

The dropdown applies to all dashboard types that have a dedicated controller `dashboard` action:

| Dashboard Type | Controller |
|---|---|
| Fund Dashboard | `FundsController#dashboard` |
| Investor Dashboard | `InvestorsController#dashboard` |
| Portfolio Company Dashboard | `InvestorsController#dashboard` |
| Aggregated Portfolio Dashboard | `InvestorsController#dashboard` |
| Generic dashboard view | `DashboardWidgetsController#dashboard` |

Landing page dashboards (`FM_LANDING_PAGE`, `LP_LANDING_PAGE`) rendered as sub-partials within entity pages are **out of scope** for the initial release, as they are not loaded via a dedicated controller action that can set up the names query.

## 7. Technical Design

### 7.1 Data Source

Named dashboards are already stored in the `dashboard_widgets` table. The selector is populated by querying:

```sql
SELECT DISTINCT name FROM dashboard_widgets
WHERE dashboard_name = ? AND entity_id = ? AND enabled = true
ORDER BY name ASC
```

### 7.2 Controller Changes

Each relevant controller's `dashboard` action gains a single additional assignment:

```ruby
@dashboard_names = DashboardWidget.enabled
  .where(dashboard_name: @dashboard_name, entity_id: current_user.entity_id)
  .distinct.pluck(:name).sort
```

Affected files:
- `app/packs/funds/funds/controllers/funds_controller.rb` — `dashboard` action
- `app/packs/core/investors/controllers/investors_controller.rb` — `dashboard` action, `setup_portfolio_dashboard`, `setup_aggregated_portfolio_dashboard`
- `app/packs/core/base/controllers/dashboard_widgets_controller.rb` — `dashboard` action

### 7.3 Turbo Frame ID (breaking change: frame ID becomes static)

Currently the Turbo Frame wrapping each dashboard view encodes `@name` in its ID:

```erb
turbo_frame_tag "#{@name.downcase.underscore}_#{@dashboard_name.downcase.underscore}_frame"
```

When switching from "Default" to "Q3 Performance", the server would respond with a different frame ID (`q3_performance_fund_dashboard_frame`), causing Turbo to fall back to a full page load because the IDs don't match.

**Fix:** Drop `@name` from the frame ID. New pattern:

```erb
turbo_frame_tag "#{@dashboard_name.parameterize.underscore}_frame", data: { turbo_action: "advance" }
```

Examples: `"fund_dashboard_frame"`, `"investor_dashboard_frame"`, `"portfolio_company_dashboard_frame"`.

The `data-turbo-action="advance"` attribute causes Turbo to push the new URL into the browser's history stack after each frame navigation, satisfying the bookmarkability requirement.

Affected frame-wrapping views:
- `app/packs/funds/funds/views/funds/dashboard.html.erb`
- `app/packs/core/investors/views/investors/dashboard.html.erb`
- `app/packs/core/base/views/dashboard_widgets/dashboard.html.erb`

### 7.4 `_dashboard.html.erb` Changes

Accept a new `dashboard_names` local (defaulting to `[]`). Render the `_dashboard_selector` partial immediately before the `<nav>` block:

```erb
dashboard_names ||= []
```

```erb
<%= render "/dashboard_widgets/dashboard_selector",
      dashboard_names: dashboard_names,
      current_name: name,
      dashboard_name: dashboard_name,
      frame_id: "#{dashboard_name.parameterize.underscore}_frame" %>
```

### 7.5 New Partial: `_dashboard_selector.html.erb`

Location: `app/packs/core/base/views/dashboard_widgets/_dashboard_selector.html.erb`

Renders a Bootstrap-styled `<form method="get">` that Turbo intercepts:

```erb
<% if dashboard_names.length > 1 %>
  <div class="dashboard-selector px-3 py-2">
    <form method="get"
          data-turbo-frame="<%= frame_id %>"
          data-turbo-action="advance">
      <input type="hidden" name="dashboard_name" value="<%= dashboard_name %>">
      <select name="name"
              class="form-select form-select-sm w-auto"
              onchange="this.form.submit()">
        <% dashboard_names.each do |n| %>
          <option value="<%= n %>" <%= "selected" if n == current_name %>><%= n %></option>
        <% end %>
      </select>
    </form>
  </div>
<% end %>
```

The `<form>` carries `data-turbo-frame` so Turbo targets the correct frame on submission. No new Stimulus controller is required.

### 7.6 Each Frame-Wrapping View Change

`dashboard_names: @dashboard_names` is added to the `render` call for the `_dashboard` partial so it is passed through.

Example for `funds/dashboard.html.erb`:

```erb
<%= turbo_frame_tag "#{@dashboard_name.parameterize.underscore}_frame", target: "_top", data: { turbo_action: "advance" } do %>
  <%= render "/dashboard_widgets/dashboard",
        dashboard_name: @dashboard_name,
        name: @name,
        dashboard_names: @dashboard_names,
        uri_params: { fund: @fund, owner_id: @fund.id, owner_type: "Fund" } %>
<% end %>
```

## 8. Edge Cases

| Scenario | Expected Behaviour |
|---|---|
| No custom widgets configured (falls back to defaults) | `@dashboard_names` is empty → no dropdown |
| Only "Default" configured | 1 entry → no dropdown |
| "Default" + 1 named dashboard | 2 entries → dropdown shown with both, sorted |
| Named dashboards exist but none named "Default" | All shown sorted; first alphabetically is pre-selected by default |
| URL with `?name=X` where X no longer exists | Widget helper falls back to defaults; no crash |
| Two different dashboard types on same page | Impossible: each uses a different `dashboard_name`-derived frame ID |
| `@dashboard_names` not set (landing page partials) | Defaults to `[]` inside `_dashboard.html.erb` → no dropdown |

## 9. Schema Changes

None. The `name` column on `dashboard_widgets` already supports this feature.

## 10. Acceptance Criteria

- [ ] No dropdown appears when only one named dashboard (or no custom widgets) exists for an entity + dashboard type.
- [ ] A sorted dropdown appears above the nav bar when two or more named dashboards exist.
- [ ] The currently active dashboard name is pre-selected in the dropdown on page load.
- [ ] Selecting a different name from the dropdown updates the dashboard content without a full page reload.
- [ ] The browser URL updates to reflect the newly selected `?name=` value after switching.
- [ ] The updated URL can be bookmarked and, when opened, loads the correct named dashboard.
- [ ] The dropdown and navigation work correctly for Fund, Investor, Portfolio Company, and Aggregated Portfolio dashboard types.
- [ ] Pages with only "Default" configured continue to work exactly as before (no regression).
- [ ] The existing dashboard navigation bar (widget anchor links, Reports dropdown) is unaffected.
