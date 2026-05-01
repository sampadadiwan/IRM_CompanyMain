# Dashboard Widgets User Guide (V9.1.87)

This guide provides a detailed reference for configuring dashboard widgets in the IRM platform. Dashboards are modular and can be customized per entity or fund using a flexible widget system.

## Table of Contents
1. [Overview](#1-overview)
2. [Global Widget Settings](#2-global-widget-settings)
3. [Metadata Configuration](#3-metadata-configuration)
4. [Widget Reference by Dashboard](#4-widget-reference-by-dashboard)
    - [Fund Dashboard](#fund-dashboard)
    - [Investor Dashboard](#investor-dashboard)
    - [Portfolio Company Dashboard](#portfolio-company-dashboard)
    - [Portfolio Dashboard](#portfolio-dashboard)
    - [Aggregated Portfolio Dashboard](#aggregated-portfolio-dashboard)
    - [Landing Pages (FM, LP, Ops)](#landing-pages)
5. [Advanced Features](#5-advanced-features)
    - [Named Dashboards](#named-dashboards)
    - [Dashboard Selector Dropdown](#dashboard-selector-dropdown)
    - [User Dashboard Preferences](#user-dashboard-preferences)
    - [Flexible KPI Charts](#flexible-kpi-charts)
    - [Embedded Documents (Excel as Grid)](#embedded-documents-excel-as-grid)
    - [Agent Charts](#agent-charts)
6. [FAQ](#6-faq)

---

## 1. Overview
Dashboards in IRM are composed of "Widgets"—individual blocks of information or functionality. Administrators can enable, disable, resize, and reorder these widgets to create a tailored experience for different users and entities.

Each dashboard type (e.g., Fund Dashboard, Investor Dashboard) can have multiple **named configurations** — separate sets of widgets with their own layout and metadata. The special name `Default` is used when no other configuration is specified. Named dashboards allow an entity to maintain several distinct views of the same data (e.g., an operational view, a compliance view, and a presentation view) and switch between them instantly.

## 2. Global Widget Settings
Every widget has three primary settings that control its appearance on the dashboard:

*   **Size**: Controls the width of the widget on the page grid.
    *   **XS**: 25% width (4 per row)
    *   **Small**: 33% width (3 per row)
    *   **Medium**: 50% width (2 per row)
    *   **Large**: 66% width
    *   **XL**: 100% width (Full row)
*   **Position**: A numerical value determining the display order (lower numbers appear first).
*   **Enabled**: A toggle to show or hide the widget on the dashboard.

## 3. Metadata Configuration
Metadata allows for deep customization of a widget's behavior. It is written as a **Ruby-style Hash**.

### Syntax Rules:
*   **Keys**: Followed by a colon (e.g., `title:`).
*   **Strings**: Must be enclosed in single quotes (e.g., `'My Title'`).
*   **Booleans**: Use `true` or `false` (no quotes).
*   **Arrays**: Enclosed in square brackets (e.g., `['XIRR', 'TVPI']`).
*   **Numbers**: Written directly (e.g., `12`).

**Example Metadata:**
```ruby
{title: 'Performance Summary', months: 12, ratio_names: ['XIRR', 'TVPI'], chart: true}
```

---

## 4. Widget Reference by Dashboard

### Fund Dashboard
Used for individual Fund pages.

#### Fund Ratios
*   **Description**: Displays performance ratios (XIRR, TVPI, DPI, etc.) with optional charts.
*   **Metadata Options**:

| Option | Type | Description |
| :--- | :--- | :--- |
| `title` | String | Custom widget title |
| `scenario` | String | Calculation scenario (Default: 'Default') |
| `ratio_names` | Array | Ratios to display, e.g., `['XIRR', 'TVPI', 'DPI']` |
| `months` | Integer | History window in months |
| `chart` | Boolean | Show/hide the chart |
| `list` | Boolean | Show/hide the data table |
| `condensed` | Boolean | Use a compact layout |
| `decimals` | Integer | Number of decimal places (Default: 2) |

#### Fund Cashflows
*   **Description**: Visualizes fund cashflow series over time.
*   **Metadata Options**:

| Option | Type | Description |
| :--- | :--- | :--- |
| `months` | Integer | History window (Default: 36) |
| `series` | String | Comma-separated series names to include |
| `chart_type` | String | `line`, `bar`, `area`, or `spline` |

#### Fund Portfolio Stats
*   **Description**: Aggregate statistics across all investments in the fund.
*   **Metadata Options**:

| Option | Type | Description |
| :--- | :--- | :--- |
| `fields` | String | Comma-separated field paths (e.g., 'Bought Amount,FMV') |
| `field_names` | String | Custom labels for the fields |
| `force_units` | String | `Lakhs`, `Crores`, or `Millions` |
| `currency` | String | Currency code (e.g., 'USD') |

---

### Investor Dashboard
Used for individual Investor profile pages.

#### Documents
*   **Description**: A powerful document browser for the investor's library.
*   **Metadata Options**:

| Option | Type | Description |
| :--- | :--- | :--- |
| `folder_id` | Integer | Limit view to a specific folder ID |
| `card_view` | Boolean | Toggle between list and grid/card view |
| `per_page` | Integer | Number of documents per page |
| `per_row` | Integer | Cards per row in card view |
| `show_tags` | Boolean | Show/hide document tags |

#### Commitments
*   **Description**: Summary of the investor's capital commitments.
*   **Metadata**: None required.

---

### Portfolio Company Dashboard
Used for individual Portfolio Company (Investee) pages.

#### Kpis (Grid View)
*   **Description**: The primary interface for viewing and charting company KPIs.
*   **Metadata Options**:

| Option | Type | Description |
| :--- | :--- | :--- |
| `categories` | String | Comma-separated categories (e.g., 'Income Statement, Balance Sheet') |
| `period` | String | `Quarter` or `Year` |
| `no_of_periods`| Integer | Number of periods to display (Default: 12) |
| `tag_list` | String | Filter by tags (e.g., 'Actual, Budget') |
| `flexible_chart`| Boolean | Enable the interactive charting system |

#### Captable
*   **Description**: Detailed capitalization table with ownership breakdowns.
*   **Metadata Options**:

| Option | Type | Description |
| :--- | :--- | :--- |
| `show_charts` | Boolean | Show ownership distribution charts |
| `diluted_chart`| String | `pie`, `donut`, or `half_donut` |
| `show_captable`| Boolean | Show the main data table |
| `ag` | Boolean | Use high-performance AG-Grid for the table |

#### Data Card
*   **Description**: Displays specific fields from the company record in a clean card format.
*   **Example**: `{cols: 2, fields: "Category:category,City:city,Sector:custom_fields.sector"}`

---

### Portfolio Dashboard
Used for the overall Portfolio overview.

#### Portfolio IRR
*   **Description**: Calculates and charts the Internal Rate of Return for the entire portfolio.
*   **Metadata Options**: `{show_table: true, show_chart: true}`

#### FMV %
*   **Description**: Pie chart showing the distribution of Fair Market Value across the portfolio.

---

### Aggregated Portfolio Dashboard
Used for cross-fund portfolio analysis.

#### Aggre. Portfolio Investments
*   **Description**: A multi-company investment table with grouping capabilities.
*   **Metadata Options**: `{show_grouped: true, group_by_column: 'portfolio_company_name'}`

#### Company Charts
*   **Description**: Sector and Company-wise breakdowns.
*   **Metadata Options**: `{plot: 'fmv,bought_amount', table_limit: 10}`

---

### Landing Pages
*   **FM Landing Page**: Includes **FM Stats**, **Managed Funds**, and **Investment Opportunities**.
*   **LP Landing Page**: Includes **My Funds**, **Offers**, **Interests**, and **Account Entries Chart**.
*   **Ops Dashboard**: Focused on internal management with **My Tasks**, **Upcoming Events**, and **Investors No Interaction**.

---

## 5. Advanced Features

### Named Dashboards

A **named dashboard** is a distinct set of widgets saved under a custom `Name` for a given dashboard type and entity. Any dashboard type supports multiple names.

| Field | Description |
| :--- | :--- |
| **Dashboard Name** | The dashboard type, e.g., `Fund Dashboard`, `Investor Dashboard` |
| **Name** | The configuration label, e.g., `Default`, `Compliance`, `Budget View` |

All widgets that share the same **Dashboard Name + Name + Entity** form one named dashboard. Widgets with `Name = Default` are the fallback shown when no specific name is requested.

**To create a named dashboard:**
1. Go to **Dashboard Widgets** in the admin menu.
2. Create one or more widgets, setting **Name** to your chosen label (e.g., `Compliance`).
3. Ensure all widgets for that named dashboard share the same **Name** value.

The same widget type can appear in multiple named dashboards with different metadata — for example, a `Fund Ratios` widget configured for `Actual` in the `Default` dashboard and for `Budget` in a `Budget View` dashboard.

---

### Dashboard Selector Dropdown

When an entity has **more than one** named dashboard configured for a dashboard type, a selector dropdown appears automatically at the right-hand end of the dashboard navigation bar.

*   The dropdown lists all available dashboard names in **alphabetical order** (or in the order defined by user preferences — see below).
*   Selecting a name immediately loads that dashboard via a Turbo Frame swap — no full page reload.
*   The selected name is reflected in the URL (`?name=Compliance`) so the view can be **bookmarked and shared**.
*   If only one named dashboard exists for an entity, the dropdown is not shown.

> **Note:** The dropdown is only visible on dashboard types rendered through the main dashboard view (Fund, Investor, Portfolio Company, and the generic Ops Dashboard). The Aggregated Portfolio Dashboard selector is planned for a future release.

---

### User Dashboard Preferences

Administrators can configure per-user preferences that control:

1. **The order** in which named dashboards appear in the dropdown.
2. **The default** dashboard loaded when no `?name=` parameter is present in the URL (i.e., the first in the sequence).

Preferences are stored as JSON on the User record under the `preferences` column with the following structure:

```json
{
  "dashboard": {
    "Fund Dashboard": {
      "sequence": "Compliance,Default"
    },
    "Investor Dashboard": {
      "sequence": "Budget View,Default"
    }
  }
}
```

The `sequence` value is a comma-separated ordered list of dashboard names. The **first name** is loaded by default when the user navigates to that dashboard page.

**Editing preferences via the User form:**

The User edit form shows a **Dashboard Preferences** section automatically when the user already has preferences saved. Each dashboard type appears as a labelled text field showing the current sequence, which can be edited inline and saved.

> The section is only shown for existing users who already have at least one dashboard preference entry. New preferences must be seeded via the Rails console or a one-off script.

**Editing preferences via the Rails console:**

```ruby
Chewy.strategy(:bypass) do
  user = User.find(103)
  user.update!(preferences: {
    "dashboard" => {
      "Fund Dashboard" => { "sequence" => "Compliance,Default" }
    }
  })
end
```

**The User show page** displays a read-only summary table of all dashboard preferences, including the full ordered sequence and the highlighted default for each dashboard type.

**Fallback behaviour:**

| Condition | Dashboard loaded |
| :--- | :--- |
| User has a sequence preference and no `?name=` in URL | First name in the sequence |
| No sequence preference and no `?name=` in URL | `Default` |
| `?name=X` is present in the URL | Always `X`, regardless of preference |
| A sequence name no longer has widgets configured | Widget helper falls back to the full default widget set |

---

### Flexible KPI Charts
The **Kpis** widget supports an interactive charting mode. Users can select multiple KPIs from the grid and choose different chart types (Line, Bar, Area) for each to create mixed-mode visualizations. These configurations can be saved and loaded later.
*See the [Flexible KPI Charts User Guide](./kpi_flexible_charts_user_guide.md) for more details.*

### Embedded Documents (Excel as Grid)
The **Embed Document** widget can render Excel files (`.xlsx`) as interactive, searchable grids directly on the dashboard.
*   **Metadata**: `{name: 'Financial Model', xlsx_as_grid: true}`

### Agent Charts
Leverage AI to generate custom visualizations based on complex data queries.
*   **Metadata**: `{title: 'AI Insights'}`

---

## 6. FAQ

**Q: Why isn't my widget showing up?**
A: Ensure the **Enabled** toggle is on and that the **Dashboard Name** matches the page you are viewing. Also, check that the **Metadata** syntax is valid Ruby (e.g., no missing commas or unquoted strings).

**Q: How do I change the order of widgets?**
A: Use the **Position** field. Widgets are sorted in ascending order (1, 2, 3...).

**Q: Can I show the same widget twice with different settings?**
A: Yes. You can add multiple instances of the same widget to a dashboard and use **Metadata** to differentiate them (e.g., two "Fund Ratios" widgets, one for 'Actual' and one for 'Budget').

**Q: What happens if I enter invalid metadata?**
A: The widget will usually fall back to its default settings. Check the "Sample Metadata" hint in the edit form for the correct format.

**Q: I've created a named dashboard but the dropdown isn't appearing.**
A: The dropdown only appears when there are **two or more** distinct named dashboards configured for the same entity and dashboard type. Check that your widgets have different `Name` values and that all are **Enabled**. If only one name is configured (e.g., just `Default`), no dropdown is shown.

**Q: How do I control which named dashboard a user sees first?**
A: Set a `sequence` preference on the user record. The first name in the sequence becomes the default. You can do this via the User edit form (if a preference already exists) or via the Rails console. See [User Dashboard Preferences](#user-dashboard-preferences) for details.

**Q: A user has a preference set but still lands on Default.**
A: Check that the name in the sequence exactly matches the `Name` field on the dashboard widgets (case-sensitive). Also confirm the widgets for that named dashboard are enabled and belong to the correct entity.

**Q: Can I share a link to a specific named dashboard?**
A: Yes. The URL includes `?name=<dashboard-name>` whenever a named dashboard is active (e.g., `?name=Compliance`). Copy and share that URL — recipients will land on the same named dashboard directly.

**Q: The dropdown shows names in the wrong order.**
A: By default names are sorted alphabetically. To override the order for a specific user, set a `sequence` preference on their user record listing names in the desired order.

---
*For technical support or custom widget requests, please contact the system administrator.*
