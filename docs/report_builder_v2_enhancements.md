# Enhancement Design: Report Builder v2

**Status:** Proposed  
**Date:** 2026-04-23  
**Target Version:** v2.0

This document outlines the technical design for five key enhancements to the Report Builder, aimed at increasing its analytical power and operational utility.

---

## 1. Advanced Calculations & Formulas
**Goal:** Enable users to create derived columns using mathematical and logical expressions.

### Technical Design
*   **Storage:** `Report#template` will include a `formulas` array.
    ```json
    "formulas": [
      {
        "key": "calc_call_pct",
        "label": "Call %",
        "expression": "([capital_commitments.called_amount] / [capital_commitments.amount]) * 100",
        "data_type": "Percentage"
      }
    ]
    ```
*   **Execution:** A new `ReportBuilder::FormulaEvaluator` service will process rows after the `QueryEngine` merge step.
*   **Security:** Expressions will be parsed using a safe sandbox (e.g., the `Dentaku` gem) to prevent arbitrary code execution. Only white-listed column tokens and basic math/logic operators will be allowed.
*   **UI:** A "Formula Builder" modal with autocomplete for column keys and a "Test" button to validate against preview data.

---

## 2. Multi-Level Joins (Deep Discovery)
**Goal:** Allow reporting on grandchild and great-grandchild relations.

### Technical Design
*   **Path Resolution:** `AssociationResolver` will be updated to support dot-notation paths (e.g., `capital_commitments.fund.fund_manager`).
*   **Query Strategy:** `QueryEngine` (Pass 2) will become recursive.
    *   For a path `A.B.C`, it will first resolve `A`, then use the resulting foreign keys to resolve `B`, and finally `C`.
*   **Discovery:** `ReportBuilderModelDiscovery` will expose a "Drill Down" API to fetch associations of a joined model dynamically.
*   **UI:** The "Add Join" picker will support nested navigation, allowing users to "drill into" a table to see its related tables.

---

## 3. Scheduling & Automated Delivery
**Goal:** Automate the generation and distribution of reports.

### Technical Design
*   **Schema:** New `report_schedules` table.
    *   `report_id`: FK to Reports.
    *   `frequency`: Enum (daily, weekly, monthly).
    *   `recipients`: Array of email addresses.
    *   `cron_expression`: Standard cron string.
    *   `active`: Boolean toggle.
*   **Automation:** A recurring Sidekiq-cron job (`ReportBuilder::SchedulerJob`) will run hourly to check for due reports.
*   **Delivery:** Successful exports will be attached to a `ReportMailer` and sent to the recipient list.
*   **UI:** A "Schedule" tab in the Builder's right panel for managing delivery settings.

---

## 4. Enhanced Pivot Capabilities
**Goal:** Support multi-dimensional pivots and hierarchical row grouping.

### Technical Design
*   **Multi-Dimension:** `ReportBuilderPivotAggregator` will be updated to accept an array of `categories`. It will generate composite keys (e.g., `Fund A | 2025`) for the dynamic columns.
*   **Row Grouping:** A new `group_rows_by` attribute in the template.
*   **Excel Integration:** The `xlsx_exporter.rb` will utilize `caxlsx`'s `outline_level` feature to create collapsible row groups in the final export based on the grouping attribute.
*   **UI:** The Pivot configuration panel will allow multi-selection for categories and a "Group Rows By" dropdown.

---

## 5. "Save as View" Integration
**Goal:** Transform custom reports into live, interactive views on standard index pages.

### Technical Design
*   **Metadata:** `Report` model will include `is_view: boolean` and `view_target: string` (e.g., `investors_index`).
*   **Controller Hook:** Standard index actions (e.g., `InvestorsController#index`) will check for a `view_id` parameter.
*   **Execution:** If a `view_id` is present, the controller will delegate data fetching to `ReportBuilderQueryEngine` instead of the default ActiveRecord scope.
*   **UI:** 
    *   A "Save as View" checkbox in the Builder.
    *   Custom views will appear in the "Views" dropdown on the target index page.
    *   Standard Ransack search bars on the index page will dynamically update the report's `root_filters`.

---

## Implementation Roadmap

| Phase | Feature | Complexity |
|-------|---------|------------|
| 1 | Multi-Level Joins | Medium |
| 2 | "Save as View" | Medium |
| 3 | Advanced Formulas | High |
| 4 | Scheduling | Low |
| 5 | Enhanced Pivots | High |

---

## 6. UX Upgrade: "Intelligent Builder"
**Goal:** Simplify the user experience to handle the increased complexity of v2 features.

### Design Principles
*   **Progressive Disclosure:** Hide advanced features (formulas, deep joins, scheduling) until explicitly requested to keep the interface clean for simple reports.
*   **Contextual Assistance:** Provide "What's this?" tooltips and inline examples for complex logic like formulas and pivots.

### Key UX Enhancements
*   **Visual Join Map:** 
    *   Instead of a flat list of joins, provide a small, interactive **Relationship Map** (mini-graph) showing how the Root model connects to joined and deep-joined tables.
    *   Users can click nodes in the map to jump to that table's column configuration.
*   **Formula "Playground":**
    *   A side-by-side editor where users can see a live preview of their formula's result on the first 5 rows of data as they type.
    *   Syntax highlighting for column tokens `[Column Name]` and operators.
*   **Smart Defaults & Templates:**
    *   **"Quick Start" Gallery:** A library of pre-configured report templates (e.g., "Capital Call Summary", "Investor KYC Audit").
    *   Selecting a template pre-fills the joins, columns, and formulas, which the user can then tweak.
*   **Drag-and-Drop Filter Logic:**
    *   A visual "Filter Canvas" where users can drag filter rows into groups to create complex `(A AND B) OR C` logic without understanding boolean syntax.
*   **Unified Search (Command Palette):**
    *   A global search bar (`Cmd+K`) within the builder that searches across all available columns, joined tables, and even builder actions (e.g., "Add a formula", "Schedule this report").
*   **"View Mode" vs "Build Mode":**
    *   A toggle to switch between a clean **View Mode** (focused on the data preview and filters) and **Build Mode** (focused on the structure and configuration).

