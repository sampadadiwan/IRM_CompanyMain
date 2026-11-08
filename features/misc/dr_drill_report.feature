@rack_test
Feature: A DR run report explains itself
  Every disaster-recovery run writes a report, HTML and Markdown, that a manager or auditor
  reads without the engineer: the answer first, every problem with what to do, every step and
  check explained, light and self-contained. Both copies come from one model, and every step and
  check takes its plain name and explanation from one catalog.

  These scenarios build the model from the 2026-11-08 staging drill's real figures (22 checks
  on each of 2 servers, one warning each) and render it in memory - nothing reads AWS or a run.

  # H1 — Happy path: the answer and the tiles add up
  Scenario: A passed drill opens with its answer and figures that add up
    Given the 2026-11-08 staging drill's run data
    When the report model is built
    Then the headline is "Staging recovered in ap-south-2 and verified: 12:04"
    And the tiles read "12:04", "1:59", "42 / 44" and "0.4 h"
    And needs attention lists 1 item: "Primary backup schedule" seen on "both servers"

  # H2 — Happy path: checks shown once, grouped, one column per server
  Scenario: Checks are grouped by layer with one row per check
    Given the 2026-11-08 staging drill's run data
    When the report model is built
    Then the check groups are "App servers, Requests through the app, Data, Database servers, Backups"
    And there are 22 check rows with a result for each of 2 servers

  # H3 — Happy path: every step has a plain name and an explanation
  Scenario: Every step is explained
    Given the 2026-11-08 staging drill's run data
    When the report model is built
    Then every step has a plain name and a "What this does" explanation
    And step 7 is named "Restore the database from backups"

  # E1 — Edge case: a check one server did not report
  Scenario: A check reported by only one server leaves the other cell empty
    Given the 2026-11-08 staging drill's run data
    And only the first server reports "Static website — skipped"
    When the report model is built
    Then the "Public website" row has no result for the second server

  # E2 — Edge case: a check the catalog does not know is shown, not dropped
  Scenario: An unknown check appears under Other checks
    Given the 2026-11-08 staging drill's run data
    And both servers report "Frobnicator ready — yes"
    When the report model is built
    Then the "Other checks" group has a row "Frobnicator ready"

  # E3 — Edge case: per-run parts of a label are kept
  Scenario: A label with a server address keeps it in its plain name
    When the check label "Primary mysqld (10.0.3.88)" is looked up
    Then it is shown as "Primary MySQL (10.0.3.88)" under "Database servers"

  # E4 — Edge case: a real recovery is not described as a drill
  Scenario: A real recovery's summary does not claim to be a drill
    Given the 2026-11-08 staging drill's run data
    And the run was a real recovery
    When the report model is built
    Then the plain words mention "real recovery"
    And the plain words do not mention "deleted afterwards"

  # E5 — Edge case: only the server with the problem is named
  Scenario: A warning on one server names only that server
    Given the 2026-11-08 staging drill's run data
    And only the second server warns on "Primary backup cron installed"
    When the report model is built
    Then needs attention lists 1 item: "Primary backup schedule" seen on "ip-10-0-2-46"

  # E6 — Edge case: a clean run says so
  Scenario: A run where every check passed needs no attention
    Given the 2026-11-08 staging drill's run data
    And every check passed
    When the report model is built
    Then needs attention is empty
    And the plain words mention "Every check passed."

  # X1 — Error case: a run that stopped before verification
  Scenario: A failed run names the step it stopped at
    Given a staging drill that failed during step 5 before verification
    When the report model is built
    Then the headline is "Recovery stopped at step 5 · Install the app on both servers"
    And the first attention item is "Step 5 · Install the app on both servers"
    And the report says verification was not reached

  # X2 — Error case: failures come before warnings
  Scenario: A failed check is listed before a warning
    Given the 2026-11-08 staging drill's run data
    And the first server fails "Migrations current — 3 pending"
    When the report model is built
    Then the first attention item is "Database schema up to date"
    And the tiles read "12:04", "1:59", "41 / 44" and "0.4 h"

  # X4 — Error case: the catalog must cover every check and step the run can print
  Scenario: Every check dr:verify prints and every step setup_infra runs has an explanation
    When every check label in dr:verify and every step in setup_infra is looked up
    Then none of them falls into Other checks

  # H4 — Happy path: light, self-contained HTML
  Scenario: The HTML report is light and loads nothing from the network
    Given the 2026-11-08 staging drill's run data
    When the report model is built
    And the report is rendered
    Then the HTML has no dark theme and no external links
    And the HTML shows the badge "Passed"

  # H5 — Happy path: one model, so both copies have the same sections in the same order
  Scenario: The Markdown and HTML reports have the same sections in the same order
    Given the 2026-11-08 staging drill's run data
    When the report model is built
    And the report is rendered
    Then the Markdown and HTML reports list the same sections in the same order

  # X3 — Error case: transcript text is shown as text, never as markup
  Scenario: Markup in a check's output is escaped
    Given the 2026-11-08 staging drill's run data
    And the first server fails "Migrations current — <script>alert(1)</script>"
    When the report model is built
    And the report is rendered
    Then the HTML shows "&lt;script&gt;alert(1)&lt;/script&gt;" as text
    And the HTML contains no "<script>" tag
