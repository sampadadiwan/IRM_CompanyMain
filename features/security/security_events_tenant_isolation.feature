@security @rack_test
Feature: Security Events — who may see which firm's events (OWASP 2026-11 M11)
  The security event trail is firm-scoped by the policy alone: a company admin sees their own firm, CapHive support
  the firms they support while support is switched on, CapHive super users everything — including failures on
  emails with no account. Everyone else is refused, a crafted filter or download can't reach another firm, and
  there is no route that edits or deletes an event. Same style as tenant_isolation_batch1.feature: the owner is
  allowed, the other firm is refused, the direct request is refused.
  Design: openspec/changes/archive/2026-11-10-security-event-trail (business-rules.md §6 — E45, X6–X11).

  Background:
    Given today is "2026-11-09 12:00" for the security trail
    And the security cast "Rahul, Meera, Priya, Karan, Sara"
    And security events in the trail:
      | when             | firm               | kind              | outcome | account | details              |
      | 2026-11-09 10:13 | Golden Angels Fund | sign_in.failed    | failure | Priya   | {"reason":"invalid"} |
      | 2026-11-09 10:22 | Golden Angels Fund | role.granted      | success | Rahul   | {"role":"approver"}  |
      | 2026-11-09 10:30 | Beta Capital       | sign_in.succeeded | success | Sara    |                      |
      | 2026-11-09 03:12 | none               | sign_in.failed    | failure | ghost   | {"reason":"invalid"} |

  # E45 — Edge case: support sees only the firm it supports; super sees every firm and the no-firm rows
  Scenario: E45 Support and super scope
    Given the security cast "Anil, Divya"
    And "Anil" supports the firm "Golden Angels Fund"
    When "Anil" opens Security Events
    Then "Anil" sees only events of "Golden Angels Fund"
    When "Divya" opens Security Events
    Then "Divya" sees only events of "Beta Capital, CapHive only, Golden Angels Fund"

  # X6 — Error case: an employee opening the screen by URL is refused, as everywhere else
  Scenario: X6 Employee refused
    When "Karan" opens Security Events
    Then "Karan" sees "Access Denied"

  # X7 — Error case: an investor is refused the same way
  Scenario: X7 Investor refused
    When "Priya" opens Security Events
    Then "Priya" sees "Access Denied"

  # X8 — Error case: another firm's admin asking for firm A by query still gets only their own firm
  Scenario: X8 Other firm by query
    When "Sara" opens Security Events with "q[entity_id_eq]=1&q[category_eq]="
    Then "Sara" sees the Security Events list with 1 row
    And the Security Events list of "Sara" has the events "Signed in"

  # X9 — Error case: a crafted download for firm A gives firm B's admin only firm B's rows
  Scenario: X9 Download re-scoped
    When "Sara" downloads the security events with "q[entity_id_eq]=1"
    Then "Sara" is emailed a security spreadsheet with 1 event row of "Beta Capital"

  # X10 — Error case: a firm that switches support off disappears from CapHive support's list
  Scenario: X10 Support without support switched on
    Given the security cast "Anil"
    And "Anil" supports the firm "Golden Angels Fund"
    And the firm "Golden Angels Fund" has support switched off
    When "Anil" opens Security Events
    Then "Anil" sees the help "No security events in this period."

  # X11 — Error case: there is no route to edit or delete an event
  Scenario: X11 No write routes
    When "Rahul" sends "DELETE" to "/security_events/1"
    Then the write route answer is 404 and the event is unchanged
    When "Rahul" sends "PATCH" to "/security_events/1"
    Then the write route answer is 404 and the event is unchanged
