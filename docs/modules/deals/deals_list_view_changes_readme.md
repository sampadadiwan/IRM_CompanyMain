# Deals List View Technical README

## Scope
This document summarizes the technical changes implemented for:

1. Deal investor sidepanel close behavior during redirects/navigation.
2. "All Documents" navigation from sidepanel contexts.
3. Configurable Deal List analytics cards from Deal New/Edit.
4. Persistence and rendering fixes for analytics card selection.

## Change Set Overview

### 1) Sidepanel Lifecycle and Navigation Safety

Problem:
- The Deal Investor offcanvas sidepanel could remain visible (or leave backdrop artifacts) after redirect/navigation.

Implementation:
- Added a Turbo navigation hook to proactively close the sidepanel on page navigation.
- Kept outside-click close handling and cleanup logic robust during connect/disconnect cycles.

Primary implementation file:
- app/javascript/controllers/deals_list_ag_grid_controller.js

Key behavior:
- On turbo:before-visit, the controller calls closeSidepanel().
- On disconnect(), listeners are removed to avoid stale behavior after Turbo page swaps.

### 2) Sidepanel Frame Top-Level Navigation

Problem:
- Navigation originating from offcanvas content could remain scoped in frame contexts instead of fully leaving the panel flow.

Implementation:
- Forced the sidepanel root turbo frame target to _top.

Primary implementation file:
- app/packs/startups/deals/views/deals/_list_view_sidepanel.html.erb

Key behavior:
- deal_investor_frame defaults to top-level navigation, avoiding nested frame trapping during redirects.

### 3) "All Documents" Button Behavior from Sidepanel

Problem:
- Clicking "All Documents" from sidepanel-related views could leave the sidepanel visible while navigating.

Implementation:
- Explicitly set the link to target top-level Turbo navigation.
- Added an explicit close sidepanel action on click.

Primary implementation file:
- app/packs/core/documents/views/documents/_tree_view.html.erb

Key behavior:
- "All Documents" now includes:
  - data-turbo-frame="_top"
  - click->deals-list-ag-grid#closeSidepanel

### 4) Configurable Analytics Cards on Deal List View

Requirement implemented:
- Configure analytics cards from Deal New/Edit via a multi-select.
- Allowed selections:
  - Total Target
  - Committed (Active)
  - Conversion Rate
  - Stagnant Leads (>7d)
  - Total of Deal Amount
  - Primary Amount
  - Secondary Amount
  - Completed %
  - Number of Deal Investors

#### 4.1 Model additions

Primary implementation file:
- app/packs/startups/deals/models/deal.rb

Added:
- ANALYTICS_STAT_OPTIONS constant mapping storage keys to default labels.
- analytics_stats getter/setter backed by deal.json_fields["analytics_stats"].
- normalize_analytics_stats to whitelist allowed keys and normalize row hashes.
- Fallback behavior: if empty/invalid, default to the legacy default analytics rows.

#### 4.2 Form configuration (New/Edit Deal)

Primary implementation file:
- app/packs/startups/deals/views/deals/_form.html.erb

Added:
- Row-based analytics stats editor modeled after grid columns:
  - stat selector dropdown
  - custom title input
  - add/remove row controls
- Stimulus controller: app/javascript/controllers/deal_analytics_stats_controller.js

#### 4.3 Strong params and assignment flow

Primary implementation file:
- app/packs/startups/deals/controllers/deals_controller.rb

Added/updated:
- analytics_stats: [] in deal_params.
- assign_deal_form_params(deal) helper.

Persistence fix:
- create/update now use assign_deal_form_params(deal) so analytics_stats assignment occurs after base attribute assignment, preventing accidental overwrite by other json_fields/properties assignment paths.

#### 4.4 List view analytics rendering

Primary implementation file:
- app/packs/startups/deals/views/deals/_list_view_analytics.html.erb

Updated behavior:
- Builds a cards_by_key map for allowed metrics only.
- Renders only the selected rows from deal.analytics_stats.
- Uses each saved row's label as the card subtitle.
- Falls back to all cards if no valid selection is available.
- Keeps descriptive explanatory text on each card.
- Uses responsive column classes based on number of selected cards.

Current metric computation:
- Total of Deal Amount: deal.amount
- Primary Amount: sum(primary_amount_cents)
- Secondary Amount: sum(secondary_investment_cents)
- Completed %: completed_count / total_investors (statuses Complete/Completed)
- Number of Deal Investors: total count

## Files Touched

1. app/javascript/controllers/deals_list_ag_grid_controller.js
2. app/packs/startups/deals/views/deals/_list_view_sidepanel.html.erb
3. app/packs/core/documents/views/documents/_tree_view.html.erb
4. app/packs/startups/deals/models/deal.rb
5. app/packs/startups/deals/controllers/deals_controller.rb
6. app/packs/startups/deals/views/deals/_form.html.erb
7. app/packs/startups/deals/views/deals/_list_view_analytics.html.erb

## Data Contract

Storage location:
- deal.json_fields["analytics_stats"]

Supported values:
- total_deal_amount
- primary_amount
- secondary_amount
- completed_percent
- deal_investors_count

Fallback:
- If missing/empty after normalization, all supported stats are shown.

## Validation and Manual QA Checklist

1. Open Deal Edit page.
2. Select a subset in Analytics Stats multi-select.
3. Save deal.
4. Open Deal List view (show/list_view).
5. Confirm only selected cards are displayed.
6. Confirm card descriptions are visible.
7. Open investor sidepanel and click All Documents.
8. Confirm sidepanel closes and navigation completes at page level.
9. Navigate between pages while sidepanel is open.
10. Confirm no stuck offcanvas/backdrop remains.

## Notes

- Some editor diagnostics in this workspace report ERB syntax warnings for partials even when runtime rendering is valid; treat runtime rendering and Rails view behavior as source of truth.
- No schema migration was required for analytics selection because data is persisted in json_fields.
