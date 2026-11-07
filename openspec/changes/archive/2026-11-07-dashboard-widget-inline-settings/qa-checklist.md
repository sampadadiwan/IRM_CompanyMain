# Widget settings in place — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail. Row IDs match the design's worked
> examples (H/E/X) and journeys (J).

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey step ·
**R** = Role sweep · **C** = Cross-cutting check

---

## Contents

- [Test Setup](#test-setup)
- [Happy Path](#happy-path)
- [Edge Cases](#edge-cases)
- [Error Cases](#error-cases)
- [UI Journeys](#ui-journeys)
- [Role Sweep](#role-sweep)
- [Cross-cutting Checks](#cross-cutting-checks)
- [Sign-off](#sign-off)

---

## Test Setup

| Item | Detail |
|---|---|
| Environment | Staging |
| Accounts | A company admin of Demo Capital; the same user switched to the investor role; an LP of Demo Capital |
| Second entity | A user of another firm with a saved Portfolio Dashboard widget (note its widget id) |
| Seed data | A fund with 3 held companies; Valuation Freshness on its Portfolio tab; an Ops Dashboard with no widgets set up |
| Background work | None |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Icon on every widget | Admin | 1. Open the fund › Portfolio tab 2. Point at each widget | Each widget shows the sliders icon at its top-right; tooltip "Change this widget's settings" | | |
| ☐ | H2 | Popup shows current values | Valuation Freshness saved with 90 / 180 / 15, XL | 1. Click its icon | "Valuation Freshness settings"; fields 90, 180, 15; Size XL; note "Changes apply to everyone in your firm who uses the Default layout of the Portfolio Dashboard" | | |
| ☐ | H3 | Only that widget reloads | H2 | 1. Rows to show 2 2. Save and refresh | Popup closes; widget shimmers, then shows 2 rows and "Showing 2 of 3"; other widgets do not flicker; "Valuation Freshness updated" appears | | |
| ☐ | H4 | Size change | H2 | 1. Size Medium 2. Save and refresh | The widget takes half the row | | |
| ☐ | H5 | First save on defaults | Ops Dashboard never set up | 1. Open Ops Dashboard 2. Change a setting of My Tasks 3. Save and refresh | Page refreshes in place; the same 4 widgets in the same order; My Tasks shows the change; Widgets page lists 4 Ops rows | | |
| ☐ | H6 | Aggregated filters kept | Aggregated Portfolio Dashboard filtered to one company | 1. Valuation Freshness › icon 2. Rows to show 1 3. Save | The reloaded widget lists only the filtered company | | |
| ☐ | H7 | Own-card widget | Fund Dashboard | 1. Point at Fund Stats 2. Click the icon | Popup "Fund Stats settings" opens | | |
| ☐ | H8 | Widget without settings | A widget with no settings | 1. Click its icon | "This widget has no settings of its own" and Size only | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Cancel | H2 | 1. Rows to show 5 2. Cancel | Popup closes; widget unchanged; reopening shows 15 | | |
| ☐ | E2 | ✕ | H2 | 1. Rows to show 5 2. ✕ | Same as E1 | | |
| ☐ | E3 | Blank falls back | 15 saved | 1. Clear Rows to show 2. Save | Widget shows up to 15 rows (its default) | | |
| ☐ | E4 | FM home saves only what it shows | Home page never set up | 1. Change a widget on the home page 2. Save | Widgets page lists exactly the 4 widgets the home page showed | | |
| ☐ | E5 | Second save adds nothing | After H5 | 1. Save My Tasks again | Still 4 Ops rows | | |
| ☐ | E6 | Two quick first saves | Ops never set up; two browser tabs | 1. Save in tab 1 2. Save another widget in tab 2 | 4 Ops rows; both changes kept | | |
| ☐ | E7 | Reduced motion | OS "reduce motion" on | 1. Save a change | Same result, no fades or highlight | | |
| ☐ | E8 | Unknown widget key | — | Ask a developer to open a dashboard URL with `only_widget=nope` | Empty area, no error page | | |
| ☐ | E9 | Extra saved setting kept | A widget with an extra raw setting | 1. Change another setting 2. Save 3. Open the full widget page | The extra setting is still there | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Investor role | Admin switched to investor role | 1. Open a dashboard 2. Ask a developer to request the settings URL | No icons; request refused | | |
| ☐ | X2 | Other firm's widget | Other firm's widget id | Ask a developer to request its settings and a save | Refused; that widget unchanged | | |
| ☐ | X3 | LP company dashboard | LP login | 1. Open the LP company dashboard | No icons | | |
| ☐ | X4 | Expression refused | H2 | 1. Advanced › raw settings: `{limit: exit}` 2. Save | Popup stays open with the reason; widget unchanged | | |
| ☐ | X5 | Unknown size | — | Ask a developer to post Size "Huge" | "Size is not one of XL, Large, Medium, Small, XS"; unchanged | | |
| ☐ | X6 | Unknown dashboard name | — | Ask a developer to request settings for dashboard "Nope" | Not found; nothing saved | | |
| ☐ | X7 | Extra fields ignored | H2 | Ask a developer to post another firm's id and another widget name with a save | Only the settings/size change | | |

---

## UI Journeys

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | J1.1 | Icon appears on hover and focus | Admin | Point at a widget; tab to it with the keyboard | Icon fades in | | |
| ☐ | J1.2 | Popup opens smoothly | J1.1 | Click the icon | Popup rises into view; page dims | | |
| ☐ | J1.3 | Saving shows progress | J1.2 | Save and refresh | Button shows a spinner and is disabled | | |
| ☐ | J1.4 | Refresh feedback | J1.3 | — | Shimmer, fade-in, short highlight, toast for ~3 s | | |
| ☐ | J1.5 | Focus returns | J1.4 | — | Keyboard focus back on the widget's icon | | |
| ☐ | J1.6 | Full page link | J1.2 | Click "Open the full widget page" | The widget's edit page opens | | |

## Role Sweep

| ☐ | ID | Role | Icon shown | Popup / save allowed |
|---|---|---|---|---|
| ☐ | R1 | Company admin | Yes | Yes |
| ☐ | R2 | Employee (non-admin) | Yes | Yes |
| ☐ | R3 | Same user in investor role | No | Refused |
| ☐ | R4 | LP user | No | Refused |
| ☐ | R5 | Other firm's user | No (on their own dashboards: yes, for their widgets) | Refused for this firm's widgets |

## Cross-cutting Checks

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | C1 | Emails | Save several changes | No emails or alerts are sent | | |
| ☐ | C2 | Narrow width | Phone width, open a popup | Popup fits; fields stack; icon visible | | |
| ☐ | C3 | Isolation | Other firm's user opens their dashboard | Never sees this firm's widgets | | |
| ☐ | C4 | Regression: widget edit page | Edit a widget the old way | Works as before | | |
| ☐ | C5 | Regression: every dashboard | Open fund, portfolio, aggregated, company, investor, ops, home | All widgets render as before, plus the icon | | |
| ☐ | C6 | Dark theme | Switch theme to dark | Popup, shimmer and toast readable | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
