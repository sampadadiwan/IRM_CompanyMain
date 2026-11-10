Feature: Deals index grid view
  The Deals index shows deals as cards (the default) or as a grid. The grid icon in the heading switches
  views; the choice is remembered. The grid's columns are the firm's own, changed with the columns icon
  like every other grid (Deal::LIST_COLUMNS until the firm saves its own).

Scenario: Switch to the grid view, see the standard columns, and come back to it
  # H1 — Happy path: the grid lists the same deals as the cards, with the standard columns
  Given Im logged in as a user "" for an entity "entity_type=Company;enable_deals=true"
  And the user has role "company_admin"
  And given there is a deal "name=Series A Round;status=Open" for the entity
  And I am at the deals page
  Then the deals index should show the "cards" view
  When I switch the deals index to the "grid" view
  Then the deals index should show the "grid" view
  And the "deals" table headings should be "Name, Amount, Status, Start Date, End Date, Tags"
  And the "deals" table should show "Series A Round"
  # E1 — Edge case: an open deal's status is a success (green) badge
  And the deal "Series A Round" should show a "bg-success" status badge "Open"
  # E2 — Edge case: the choice is remembered on the next visit without ?view=
  When I am at the deals page
  Then the deals index should show the "grid" view
  When I switch the deals index to the "cards" view
  Then the deals index should show the "cards" view

Scenario: Change the grid's columns with the columns icon
  # H2 — Happy path: removing a column saves the firm's Deal columns and the grid follows
  Given Im logged in as a user "" for an entity "entity_type=Company;enable_deals=true"
  And the user has role "company_admin"
  And given there is a deal "name=Series B Round;status=Closed" for the entity
  And I am at the deals page
  When I switch the deals index to the "grid" view
  And I open the columns panel
  And I remove the column "tags"
  And I save the columns
  Then the columns panel should close
  And the "deals" table headings should be "Name, Amount, Status, Start Date, End Date"
  And my firm's "Deal" columns should be "name_link, amount, status_badge, start_date, end_date"
  # E3 — Edge case: a closed deal's status is a secondary (grey) badge
  And the deal "Series B Round" should show a "bg-secondary" status badge "Closed"
