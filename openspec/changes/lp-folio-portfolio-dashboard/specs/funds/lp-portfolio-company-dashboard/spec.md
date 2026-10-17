# Spec Delta

## Purpose

Gives LPs one page per portfolio company — the LP Company Dashboard — built from the fund manager's
existing Portfolio Company Dashboard widgets that are marked safe to share, and retires the
per-holding preview page it replaces.

## ADDED Requirements

### Requirement: Company-level Show to LPs switch
Each portfolio company SHALL have a Show to LPs switch, changed from the company page by fund team
members who may update the company. Setting it SHALL be idempotent. Turning it off SHALL ask for
confirmation. The switch alone SHALL NOT grant access: an LP also needs access to a fund that holds
the company, a fund view other than *Hidden from LPs*, and the company in their visible set.

#### Scenario: Fund team shows a company to LPs
- **WHEN** a fund team member with update permission clicks Show to LPs on Acme Robotics
- **THEN** the switch is on, the button reads Hide from LPs, and a Visible to LPs badge is shown

#### Scenario: Hide from LPs asks for confirmation
- **WHEN** the fund team member clicks Hide from LPs
- **THEN** a confirmation popup explains "LPs will no longer be able to open this company's page. Their portfolio list still shows the company." and the switch turns off only after confirming

#### Scenario: Repeated clicks are idempotent
- **WHEN** Show to LPs is submitted twice in quick succession
- **THEN** the switch is on once and no error is shown

#### Scenario: Only permitted fund team can change the switch
- **WHEN** an LP, or a fund team member without update permission, submits the switch change directly
- **THEN** the request is refused and the switch is unchanged

#### Scenario: Switch alone grants nothing
- **WHEN** a company's switch is on but the LP's fund view is *Hidden from LPs*
- **THEN** the LP cannot open the company page

### Requirement: LP layouts
Any Portfolio Company Dashboard layout of a fund manager whose comma-separated name includes the tag
"LP" (compared ignoring case and spaces) SHALL be an LP layout, e.g. "LP", "LP, FinTech", "LP, D2C".
Layout names SHALL allow up to 100 characters. Only these widget types SHALL be accepted in an LP
layout: Data Card, Key KPIs,
KPIs, KPI Performance Table, Valuations, Portfolio Investments, Portfolio Stats, Embed Document. Any
other type SHALL be refused, including by direct request. Changing an LP layout SHALL NOT change
any other layout. A "Set up LP layout" action SHALL create the "LP" layout with Data Card, Key KPIs
and Valuations when it does not exist, and do nothing when it does. A "New LP layout for a tag"
action SHALL create "LP, <tag>" as a copy of the "LP" layout's widgets.

#### Scenario: Fund team sets up the LP layout
- **WHEN** a fund team member with dashboard permission clicks Set up LP layout and no LP layout exists
- **THEN** an LP layout is created with Data Card, Key KPIs and Valuations, and the layout selector shows it

#### Scenario: Set up twice creates nothing new
- **WHEN** Set up LP layout is submitted again
- **THEN** no widgets are added and the existing layout opens

#### Scenario: Fund team adds an LP-safe widget to the LP layout
- **WHEN** a fund team member adds a KPIs widget to the LP layout
- **THEN** it is saved and appears on LP company pages in its configured position and size

#### Scenario: Internal widgets cannot be added to the LP layout
- **WHEN** a request adds a Notes widget to the LP layout, or moves an existing Notes widget into it
- **THEN** the save is refused with "This widget can't be added to an LP layout: it isn't safe to show LPs."

#### Scenario: Widget form lists only LP-safe types for the LP layout
- **WHEN** a fund team member opens Add widget on the LP layout
- **THEN** only the LP-safe types are offered, with the help text "LP layout: only widgets that are safe to show LPs are listed."

#### Scenario: Disabled widget is never shown
- **WHEN** a widget in the LP layout is disabled
- **THEN** it does not appear on any LP Company Dashboard

#### Scenario: New LP layout for a tag copies LP
- **WHEN** a fund team member creates a new LP layout for the tag "FinTech"
- **THEN** an "LP, FinTech" layout is created with copies of the "LP" layout's widgets, and editing it leaves "LP" unchanged

#### Scenario: Long layout names are accepted
- **WHEN** a fund team member names a layout "LP, Enterprise Infrastructure - Software"
- **THEN** it is saved

#### Scenario: Only the exact LP tag marks an LP layout
- **WHEN** a layout is named "LPX" or "Help"
- **THEN** it is an internal layout, and widgets in it are never shown to LPs

#### Scenario: Internal layouts are unaffected
- **WHEN** the fund team reorders or removes LP layout widgets
- **THEN** the Default and other internal layouts are unchanged

### Requirement: Company tags choose the LP layout and narrow its widgets
For a shared company, LPs SHALL see the LP layout whose tags other than "LP" match the most of the
company's tags (ignoring case and surrounding spaces). Layouts with no enabled widgets SHALL be
skipped. A tie SHALL go to the layout name that comes first alphabetically. With no matching
tag-specific layout, the "LP" layout SHALL be used; with none, only the holdings card. Within the
chosen layout, a widget with tags SHALL show only when the company has one of those tags, and an
untagged widget SHALL show for every company. Only the company's tags SHALL be used, never the
viewing LP user's tags.

#### Scenario: Tag-specific layout replaces LP
- **WHEN** layouts "LP" and "LP, FinTech" exist and the shared company is tagged "Fintech"
- **THEN** LPs see the "LP, FinTech" layout's widgets and none of the "LP" layout's

#### Scenario: Untagged company uses LP
- **WHEN** the shared company has no tag matching any tag-specific LP layout
- **THEN** LPs see the "LP" layout

#### Scenario: Most matching tags wins
- **WHEN** layouts "LP, FinTech" and "LP, FinTech, SAAS" exist and the company is tagged FinTech and SAAS
- **THEN** LPs see "LP, FinTech, SAAS"

#### Scenario: Tie goes to the first name
- **WHEN** layouts "LP, D2C" and "LP, FinTech" both match one tag of a company tagged D2C and FinTech
- **THEN** LPs see "LP, D2C"

#### Scenario: Empty matching layout is skipped
- **WHEN** "LP, FinTech" has no enabled widgets and the company is tagged FinTech
- **THEN** LPs see the "LP" layout

#### Scenario: No LP layout at all
- **WHEN** the fund manager has no LP layout
- **THEN** LPs see only the holdings card

#### Scenario: Widget tag narrows a widget within the layout
- **WHEN** the "LP" layout has a KPIs widget tagged "NBFC" and two shared companies, one tagged NBFC and one not
- **THEN** LPs see that widget for the NBFC company only, and the layout's untagged widgets for both

#### Scenario: Viewer's own tags are ignored
- **WHEN** the viewing LP user carries the tag "NBFC" and the company does not
- **THEN** the NBFC-tagged widget is not shown

### Requirement: Fund team is guided to the LP layout
Wherever the fund team shares with LPs, tooltips and info notices SHALL explain that LPs see the LP
Dashboard layout and link to it: the company page's Show to LPs button and header, the Portfolio
Company Dashboard settings and layout selector, the widget form, the Preview as LP banner, the fund's
LP portfolio view tooltip, and the holding page where the retired buttons were.

#### Scenario: Show to LPs tooltip explains what LPs see
- **WHEN** a fund team member hovers Show to LPs on a company page
- **THEN** the tooltip reads "LPs who hold this company will be able to open its page. They see the holdings card and the widgets of the LP layout that matches this company's tags."

#### Scenario: Company page names the layout LPs see
- **WHEN** a company tagged FinTech is shared and "LP, FinTech" is chosen for it
- **THEN** the company page shows "LPs see the "LP, FinTech" layout for this company (matched on its tag FinTech)." with an Open layout link

#### Scenario: Company page warns about a tie
- **WHEN** two LP layouts match a shared company equally
- **THEN** the company page warns "Two LP layouts match this company's tags ("LP, D2C" and "LP, FinTech"). LPs see "LP, D2C". Remove a tag or a layout to choose."

#### Scenario: Company shared with no usable LP layout
- **WHEN** a company's switch is on and no LP layout has enabled widgets for it
- **THEN** the company page shows "LPs see only the holdings card for this company. Add widgets to an LP layout" with a Set up LP layout link

#### Scenario: Company shared but every holding fund hides its portfolio
- **WHEN** a company's switch is on and every fund holding it has the view *Hidden from LPs*
- **THEN** the company page shows "No LP can open this page yet: every fund holding this company hides its portfolio from LPs. Change it in Fund › Edit › LP portfolio view."

#### Scenario: Dashboard settings invite setting up the LP layout
- **WHEN** a fund team member opens the Portfolio Company Dashboard settings and no LP layout exists
- **THEN** an info notice explains the LP layout and offers Set up LP layout

#### Scenario: LP layout explains itself
- **WHEN** the "LP, FinTech" layout is selected in settings
- **THEN** an info notice says LPs see it for shared companies tagged FinTech and how many use it today, and the selector labels it "(LPs, tag FinTech)" with the tooltip "Layouts whose name includes LP are shown to LPs. Other layouts are internal."

#### Scenario: Embed Document help on the LP layout
- **WHEN** a fund team member adds an Embed Document widget to the LP layout
- **THEN** the form says "Shows the company's latest document with this exact name, e.g. "Founder Video". Upload it to each company you share."

#### Scenario: Preview names the layout
- **WHEN** the fund team previews a FinTech company as Ravi
- **THEN** the banner reads "Preview — viewing as Ravi Menon (F-012). Layout: "LP, FinTech" (company tag FinTech)."

#### Scenario: Preview with no usable LP layout
- **WHEN** the fund team previews as an LP and no LP layout has enabled widgets for the company
- **THEN** the preview banner adds "This LP sees only the holdings card. Add widgets to an LP layout" with an Open LP layout link

#### Scenario: Widget tags field explained
- **WHEN** a fund team member edits a widget in an LP layout
- **THEN** the Tags field says "Optional. Show this widget only for companies with one of these tags. Leave empty for every company using this layout."

#### Scenario: Fund LP portfolio view tooltip
- **WHEN** a fund team member hovers the ⓘ next to LP portfolio view
- **THEN** the tooltip reads "Decides which holdings LPs see. To let LPs open a company's page, also switch the company to Show to LPs and set up an LP layout."

#### Scenario: Holding page points to the new place
- **WHEN** a fund team member opens a holding
- **THEN** where the old buttons were, a notice reads "Sharing with LPs has moved to the company: use Show to LPs on the company page and the LP layouts in dashboard settings." with a link to the company

### Requirement: LP Company Dashboard access
An LP SHALL be able to open a company's dashboard only when the company's switch is on, the company is
in the LP's visible set for the requested fund, and that fund's view is not *Hidden from LPs*. Company
names in the LP's holdings list SHALL be links only when the page can be opened. Every other request
SHALL be refused without showing any company data.

#### Scenario: LP opens a shared company
- **WHEN** an LP clicks a shared, visible company in their portfolio
- **THEN** the LP Company Dashboard opens for that company and fund

#### Scenario: Company outside the visible set is refused
- **WHEN** an LP opens the dashboard address of a company not in their visible set
- **THEN** they see "You do not have access to this company."

#### Scenario: Company switched off
- **WHEN** a visible company's switch is off
- **THEN** its name is plain text in the LP's list and its dashboard address shows "No company information has been shared yet."

#### Scenario: LP of another fund manager is refused
- **WHEN** an LP who has no access to any fund holding the company opens its dashboard address
- **THEN** they see "You do not have access to this company."

#### Scenario: Fund the LP cannot access is refused
- **WHEN** an LP opens a company dashboard naming a fund they have no access to
- **THEN** they see "You do not have access to this company."

#### Scenario: Hidden fund view refuses the page
- **WHEN** the fund's view is *Hidden from LPs*
- **THEN** the LP Company Dashboard for that fund is refused

### Requirement: LP Company Dashboard content
The page SHALL show a holdings card for the selected fund, one row per visible holding of the company,
with instrument, quantity, average cost, fund cost and fund FMV (plus Your cost and Your FMV under the
own-share view), followed by the enabled widgets of the LP layout chosen for the company. Widget data SHALL be limited to
the selected fund and the LP's visible holdings; KPI data SHALL be Actual only. With no usable LP layout,
the page SHALL show the holdings card and "No further company information has been shared." The page
SHALL never fall back to the internal widget set and SHALL NOT show the Reports dropdown, the layout
selector or any edit or run buttons.

#### Scenario: Holdings card lists the LP's visible holdings for the selected fund
- **WHEN** an LP opens Acme for Growth Fund I
- **THEN** the holdings card shows "Series B CCPS 1,00,000 ₹2,500 ₹25.00 Cr ₹40.00 Cr"

#### Scenario: Only LP layout widgets render
- **WHEN** the chosen LP layout holds Data Card, Key KPIs and Valuations and the Default layout also holds Notes
- **THEN** the page shows Data Card, Key KPIs and Valuations, in the LP layout's order and sizes, and no Notes

#### Scenario: No internal controls for LPs
- **WHEN** an LP opens a company page
- **THEN** there is no Reports dropdown, no layout selector and no edit or run button

#### Scenario: No usable LP layout shows holdings card only
- **WHEN** no LP layout with enabled widgets applies to the company
- **THEN** the page shows the holdings card and "No further company information has been shared."

#### Scenario: KPIs are Actual only
- **WHEN** a KPI widget in the LP layout is configured to show Actual and Budget
- **THEN** LPs see only Actual KPIs

#### Scenario: KPI widget with only Budget KPIs
- **WHEN** the company has only Budget KPIs
- **THEN** the KPI widget shows "No KPIs reported yet."

#### Scenario: Widget data limited to the selected fund
- **WHEN** Acme is held by Growth Fund I and Growth Fund II and the LP views Growth Fund I
- **THEN** the Portfolio Investments and Portfolio Stats widgets show Growth Fund I holdings only

#### Scenario: Widget request outside the LP layout is refused
- **WHEN** an LP opens a company page, or requests the company's internal dashboard address
- **THEN** only the enabled widgets of the LP layout chosen for that company are rendered (widget content is rendered with the page, never fetched from a separate address), and the internal dashboard is refused

#### Scenario: Internal data addresses stay closed to LPs
- **WHEN** an LP requests the company's internal dashboard or other internal company addresses directly
- **THEN** they are refused, as before this change

### Requirement: Fund selector for companies held through several funds
When the company is visible to the LP through more than one fund with an LP portfolio view other than
*Hidden*, the page SHALL show a fund selector defaulting to the first fund alphabetically. Switching
fund SHALL reload only the holdings card and widgets for that fund.

#### Scenario: LP holding a company in two funds picks the fund
- **WHEN** an LP who holds Acme through Growth Fund I and Growth Fund II opens Acme and selects Growth Fund II
- **THEN** the selector defaulted to Growth Fund I and now shows Growth Fund II's holdings and figures

#### Scenario: Only qualifying funds are offered
- **WHEN** one of the two funds has the view *Hidden from LPs*
- **THEN** no selector is shown and only the qualifying fund's data appears

### Requirement: Embed Document plays uploaded videos
The Embed Document widget SHALL play an uploaded video document inline with standard controls, on every
dashboard that uses it, and keep its existing behaviour for spreadsheets, PDFs and Office files. On an
LP Company Dashboard it SHALL expose only the named document of that company, and SHALL be omitted when
the company has no document with that name.

#### Scenario: Founder video plays
- **WHEN** Acme has a video document named "Founder Video" and the chosen LP layout's Embed Document widget names "Founder Video"
- **THEN** the LP sees the video playing inline with standard controls

#### Scenario: Missing named document hides the widget
- **WHEN** a company has no document with the configured name
- **THEN** the widget is not shown for that company

#### Scenario: PDF embed unchanged
- **WHEN** the named document is a PDF
- **THEN** it is shown in the PDF viewer as before

#### Scenario: Latest named document is used
- **WHEN** a company has two documents named "Founder Video"
- **THEN** the most recently added one is shown

#### Scenario: Only the named document is exposed
- **WHEN** an LP views the Embed Document widget
- **THEN** no link to the company's document folder or other documents is shown

### Requirement: Preview as LP
Fund team members who may view the company SHALL be able to preview its LP Company Dashboard as a chosen
LP and fund, seeing exactly what that LP would see under a "Preview — viewing as …" banner. LPs SHALL
NOT be able to use preview.

#### Scenario: Fund team previews as an LP
- **WHEN** a fund team member chooses Preview as LP, picks Ravi and Growth Fund I
- **THEN** the page renders as Ravi would see it with the banner "Preview — viewing as Ravi Menon (F-012)"

#### Scenario: Preview for an LP without access shows the refusal
- **WHEN** the fund team previews a company as an LP for whom it is not visible
- **THEN** the preview shows "You do not have access to this company."

#### Scenario: LP cannot use preview
- **WHEN** an LP requests the preview address
- **THEN** the request is refused

### Requirement: Holding preview page retired
The per-holding preview page, its Preview and Show/Hide Portfolio buttons and the `preview` address
parameter SHALL be retired. An LP opening any holding page address SHALL be sent to the company's
dashboard for the holding's fund when allowed, and refused otherwise. Fund team users SHALL still get
the internal holding page. Holding widgets, track records and preview documents SHALL be kept in the
database but no longer shown; the holding page SHALL have no Widgets or Track Record tab.

#### Scenario: Old holding link redirects
- **WHEN** an LP opens a bookmarked holding address for a shared, visible company
- **THEN** they land on the company's LP Company Dashboard for that holding's fund

#### Scenario: Preview parameter no longer bypasses
- **WHEN** an LP adds `?preview=true` to a holding address of a company whose switch is off
- **THEN** they see "No company information has been shared yet." and no holding data

#### Scenario: Fund team holding page without retired buttons
- **WHEN** a fund team member opens a holding
- **THEN** the internal holding page shows no Preview or Show/Hide Portfolio button and no Show Portfolio attribute

#### Scenario: Holding preview content becomes read-only
- **WHEN** a fund team member opens a holding that has widgets or track records
- **THEN** there is no Widgets or Track Record tab; the records stay stored but are not shown

### Requirement: Existing holding flags carry over to companies
At release, every portfolio company with at least one live holding whose Show Portfolio flag is on
SHALL have its Show to LPs switch turned on. The carry-over SHALL be safe to run more than once and SHALL
skip holdings whose company no longer exists.

#### Scenario: Company switched on from holding flag
- **WHEN** the carry-over runs and Acme's Series B holding had Show Portfolio on
- **THEN** Acme's Show to LPs switch is on and its LPs can open the same company as before

#### Scenario: Mixed holdings carry over as on
- **WHEN** a company has one holding with Show Portfolio on and one with it off
- **THEN** the company's switch is on

#### Scenario: Carry-over is idempotent
- **WHEN** the carry-over runs a second time
- **THEN** no switch changes

#### Scenario: Carried-over company in a hidden fund stays invisible
- **WHEN** a company is switched on by the carry-over but its fund's view is *Hidden from LPs*
- **THEN** LPs still cannot see it, as before

#### Scenario: Holding of a deleted company is skipped
- **WHEN** a holding with Show Portfolio on belongs to a deleted company
- **THEN** the carry-over skips it and reports the count skipped

### Requirement: LP sharing follows the fund manager's modules
LP sharing controls, LP layouts and the LP Company Dashboard SHALL be available only to fund managers with the
fund-portfolios module. KPI widgets SHALL be offered in, and shown from, LP layouts only when the fund manager has
the KPI module.

#### Scenario: LP sharing needs the fund-portfolios module
- **WHEN** a fund manager without the fund-portfolios module opens a portfolio company page or widget settings
- **THEN** there is no LPs menu, LP notice, Preview as LP or Set up LP layout, and an LP opening a company page is refused

#### Scenario: KPI widgets need the KPI module
- **WHEN** a fund manager without the KPI module has an LP layout holding KPI widgets
- **THEN** LPs do not see those widgets, the starter LP layout leaves Key Kpis out, and no KPI widget can be added to an LP layout
